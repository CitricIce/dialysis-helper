#!/usr/bin/env python3
"""Export the Roboflow RF-DETR model to Core ML for the ArmGuard iOS app, then verify it.

Model: d-s-workspace/dialysis-connector-tip-safety-1-rfdetr-small-t1

Run on your Mac (Core ML predictions only work on macOS):

    python3 -m venv .venv && source .venv/bin/activate
    pip install "rfdetr[coreml]" roboflow pillow numpy
    export ROBOFLOW_API_KEY=your_key
    python3 scripts/export_rfdetr_coreml.py --background-class-id 0 --classes "Hand,Sterile_connector_tip" --image path/to/test_photo.jpg

If the download step fails, click "Download Weights" on the model page in Roboflow and pass
the file with --weights path/to/weights.pt instead.

Output: ios/ArmGuardCaptureProbe/ArmGuardCaptureProbe/SterileParts.mlpackage
Drag it into Xcode (tick the ArmGuardCaptureProbe target). The app reads the class names,
resolution and output names that this script stores in the model metadata.
"""
import argparse
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "ios/ArmGuardCaptureProbe/ArmGuardCaptureProbe/SterileParts.mlpackage"
MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)
THRESHOLD = 0.45  # same as CONFIDENCE_THRESH in the app


def app_kind(name):
    n = name.lower().replace(" ", "_").replace("-", "_")
    if n in {"fingertip", "thumb_tip", "index_tip", "middle_tip", "ring_tip", "little_tip"}:
        return "fingertip"
    if n in {"sterile_tip", "sterile_connector_tip", "catheter_tip", "cap_interior", "connector_opening"}:
        return "protectedOpening"
    if n in {"hand", "hands", "glove", "gloved_hand"}:
        return "hand"
    return "ignored"


def download_weights(args, dest):
    from roboflow import Roboflow
    rf = Roboflow(api_key=args.api_key)
    workspace = rf.workspace(args.workspace)
    try:
        version = workspace.project(args.project).version(args.version)
    except Exception as error:
        print(f"Could not open project '{args.project}' version {args.version}: {error}")
        print("Projects in this workspace:", getattr(workspace, "projects", lambda: "?")())
        print("Re-run with --project <slug> --version <n>, or use --weights.")
        sys.exit(1)
    models = version.models()
    ids = [str(getattr(m, "id", m)) for m in models]
    print("Models in this version:", ids)
    chosen = next((m for m, i in zip(models, ids) if args.model_hint in i), None)
    if chosen is None:
        sys.exit("No matching model. Use the correct --model-hint or pass --weights.")
    cwd = os.getcwd()
    os.chdir(dest)
    try:
        chosen.download()
    finally:
        os.chdir(cwd)
    found = sorted(list(Path(dest).rglob("*.pt")) + list(Path(dest).rglob("*.pth")))
    if not found:
        sys.exit("Download finished but no .pt/.pth file was found. Use --weights instead.")
    return found[0]


def resolve_classes(args, weights, model):
    """Map class index -> name. Roboflow-trained checkpoints often store class_names=None, and
    rfdetr then falls back to COCO names, which would silently break the app's matching."""
    import torch
    checkpoint = torch.load(str(weights), map_location="cpu", weights_only=False)
    head = checkpoint["model"]["class_embed.bias"].shape[0]
    ck_args = checkpoint.get("args")
    stored = ck_args.get("class_names") if isinstance(ck_args, dict) else getattr(ck_args, "class_names", None)
    print(f"Checkpoint class slots: {head}; stored class names: {stored}")
    if args.background_class_id is None:
        sys.exit("Specify --background-class-id from the training layout (0 for this project's reserved slot, -1 for final slot, or none).")
    background = None
    if args.background_class_id != "none":
        index = int(args.background_class_id)
        if not -head <= index < head:
            sys.exit("Background class must index one of the checkpoint's slots.")
        background = index % head
    if args.class_map:
        document = json.loads(Path(args.class_map).read_text())
        if "categories" in document:
            mapping = {int(category["id"]): category["name"] for category in document["categories"]}
        else:
            mapping = {int(key): value for key, value in document.items()}
    else:
        if args.classes:
            names = [n.strip() for n in args.classes.split(",") if n.strip()]
        elif stored:
            if isinstance(stored, dict):
                mapping = {int(key): value for key, value in stored.items()}
                names = None
            else:
                names = list(stored)
        else:
            sys.exit("The checkpoint has no class IDs/names. Supply --class-map from the training COCO categories, or --classes in actual class-ID order. Project names must not be alphabetically guessed.")
        if names is not None:
            slots = [index for index in range(head) if index != background]
            if len(names) == head:
                mapping = dict(enumerate(names))
            elif len(names) == len(slots):
                mapping = dict(zip(slots, names))
            else:
                sys.exit("Class count does not match the checkpoint's foreground slots.")
    if not mapping or any(index < 0 or index >= head or not isinstance(name, str) or not name for index, name in mapping.items()):
        sys.exit("Invalid class-ID map.")
    args.resolved_background = background
    return {str(key): value for key, value in mapping.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--api-key", default=os.environ.get("ROBOFLOW_API_KEY"))
    parser.add_argument("--workspace", default="d-s-workspace")
    parser.add_argument("--project", default="dialysis-connector-tip-safety")
    parser.add_argument("--version", type=int, default=1)
    parser.add_argument("--model-hint", default="rfdetr-small-t1")
    parser.add_argument("--weights", help="local weights.pt / checkpoint.pth (skips the download)")
    parser.add_argument("--image", help="test photo to compare Core ML decoding against rfdetr.predict")
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    parser.add_argument("--classes", help="comma-separated class names for ids 1..N, e.g. 'hand,tip' "
                        "(Roboflow reserves id 0). Needed when the checkpoint stores no names.")
    parser.add_argument("--class-map", help="JSON index-to-name map, or training COCO annotations with categories")
    parser.add_argument("--background-class-id", help="Exact training background/reserved slot: integer, -1 for final, or none")
    parser.add_argument("--fp32", action="store_true", help="export float32 (bigger, no Neural Engine)")
    args = parser.parse_args()

    work = Path(tempfile.mkdtemp(prefix="rfdetr_export_"))
    if args.weights:
        weights = Path(args.weights)
    else:
        if not args.api_key:
            sys.exit("Set ROBOFLOW_API_KEY or pass --api-key (or use --weights).")
        weights = download_weights(args, work)
    print("Weights:", weights)

    from rfdetr import RFDETRSmall
    model = RFDETRSmall(pretrain_weights=str(weights))
    resolution = int(model.model_config.resolution)
    classes = resolve_classes(args, weights, model)
    print(f"Resolution: {resolution}")
    print("Classes and how the app will use them:")
    for k, v in sorted(classes.items(), key=lambda kv: int(kv[0])):
        print(f"  {k:>2}  {v:<30} -> {app_kind(v)}")
    kinds = {app_kind(v) for v in classes.values()}
    if "protectedOpening" not in kinds:
        print("WARNING: no class looks like a sterile tip. Edit classify(_:) in CoachVisionPipeline.swift.")
    if "hand" not in kinds and "fingertip" not in kinds:
        print("NOTE: no hand class; the app will use Apple's built-in fingertip tracking only.")

    exported = model.export(format="coreml", coreml_precision="float32" if args.fp32 else "float16",
                            output_dir=str(work / "coreml"))
    package = Path(exported) if exported and Path(exported).exists() else next((work / "coreml").rglob("*.mlpackage"))

    import coremltools as ct
    ml = ct.models.MLModel(str(package))
    spec = ml.get_spec()
    inputs = list(spec.description.input)
    outputs = [o.name for o in spec.description.output]
    input_kind = inputs[0].type.WhichOneof("Type")
    print("Input:", inputs[0].name, input_kind, list(inputs[0].type.multiArrayType.shape) if input_kind == "multiArrayType" else "")
    print("Outputs (dets, labels):", outputs[:2])
    if input_kind != "multiArrayType":
        print("WARNING: input is not a MultiArray; RFDETRDetector in the app expects (1,3,R,R) floats.")

    meta = ml.user_defined_metadata
    meta["classes"] = json.dumps(classes)
    meta["dets_output"] = outputs[0]
    meta["labels_output"] = outputs[1]
    meta["resolution"] = str(resolution)
    meta["armguard_box_format"] = "normalized_cxcywh"
    meta["armguard_score_encoding"] = "logits"
    meta["armguard_background_class_id"] = str(args.resolved_background) if args.resolved_background is not None else "none"
    meta["armguard_roles"] = json.dumps({value: app_kind(value) for value in classes.values()})
    ml.short_description = "RF-DETR Small: d-s-workspace/dialysis-connector-tip-safety-1-rfdetr-small-t1"
    out = Path(args.out)
    if out.exists():
        shutil.rmtree(out)
    ml.save(str(out))
    print("Saved:", out)

    if not args.image:
        print("Tip: re-run with --image <photo> to verify the app's decoding matches Roboflow.")
        return
    from PIL import Image
    image = Image.open(args.image).convert("RGB")
    width, height = image.size

    print("\nReference (rfdetr.predict):")
    ref = model.predict(image, threshold=THRESHOLD)
    for box, cid, conf in zip(ref.xyxy, ref.class_id, ref.confidence):
        print(f"  {classes.get(str(int(cid)), cid):<28} {conf:.2f}  {np.round(box).astype(int).tolist()}")

    # Exactly what RFDETRDetector does on the phone: squash to R x R, /255, ImageNet norm, NCHW.
    x = np.asarray(image.resize((resolution, resolution), Image.BILINEAR), dtype=np.float32) / 255.0
    x = ((x - MEAN) / STD).transpose(2, 0, 1)[None].astype(np.float32)
    prediction = ml.predict({inputs[0].name: x})
    dets = np.asarray(prediction[outputs[0]], dtype=np.float32).reshape(-1, 4)
    labels = np.asarray(prediction[outputs[1]], dtype=np.float32)
    labels = labels.reshape(-1, labels.shape[-1])
    scores = 1 / (1 + np.exp(-np.clip(labels, -88, 88)))
    if args.resolved_background is not None:
        scores[:, args.resolved_background] = -np.inf
    print("\nApp decoding (Core ML package):")
    for q in np.argsort(-scores.max(axis=1)):
        score = scores[q].max()
        if score < THRESHOLD:
            break
        cx, cy, w, h = dets[q]
        box = [(cx - w / 2) * width, (cy - h / 2) * height, (cx + w / 2) * width, (cy + h / 2) * height]
        print(f"  {classes.get(str(int(scores[q].argmax())), scores[q].argmax()):<28} {score:.2f}  {np.round(box).astype(int).tolist()}")
    print("\nThe two lists should show the same classes and roughly the same boxes.")
    print("Class IDs must match training annotations; do not correct offsets by guessing.")


if __name__ == "__main__":
    main()
