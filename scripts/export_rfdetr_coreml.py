#!/usr/bin/env python3
"""Export the Roboflow RF-DETR model to Core ML for the ArmGuard iOS app, then verify it.

Model: d-s-workspace/dialysis-connector-tip-safety-1-rfdetr-small-t1

Run on your Mac (Core ML predictions only work on macOS):

    python3 -m venv .venv && source .venv/bin/activate
    pip install "rfdetr[coreml]" roboflow pillow numpy
    export ROBOFLOW_API_KEY=your_key
    python3 scripts/export_rfdetr_coreml.py --image path/to/test_photo.jpg

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
    """Mirror of CoachVisionPipeline.classify(_:) so you can see how the app will treat each class."""
    n = name.lower().replace(" ", "_").replace("-", "_")
    if "finger" in n or "thumb" in n:
        return "fingertip"
    if any(w in n for w in ("sterile", "catheter", "connector", "tip")) or n in ("cap_interior", "connector_opening"):
        return "STERILE SURFACE"
    if "hand" in n or n in ("glove", "gloved_hand"):
        return "HAND"
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
    chosen = next((m for m, i in zip(models, ids) if args.model_hint in i), models[0])
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
    names = model.class_names
    pairs = names.items() if isinstance(names, dict) else enumerate(names)
    classes = {str(int(k)): str(v) for k, v in pairs}
    print(f"Resolution: {resolution}")
    print("Classes and how the app will use them:")
    for k, v in sorted(classes.items(), key=lambda kv: int(kv[0])):
        print(f"  {k:>2}  {v:<30} -> {app_kind(v)}")
    kinds = {app_kind(v) for v in classes.values()}
    if "STERILE SURFACE" not in kinds:
        print("WARNING: no class looks like a sterile tip. Edit classify(_:) in CoachVisionPipeline.swift.")
    if "HAND" not in kinds and "fingertip" not in kinds:
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
    scores = 1 / (1 + np.exp(-labels)) if (labels.min() < 0 or labels.max() > 1) else labels
    if dets.max() > 1.5:
        dets = dets / resolution
    print("\nApp decoding (Core ML package):")
    for q in np.argsort(-scores.max(axis=1)):
        score = scores[q].max()
        if score < THRESHOLD:
            break
        cx, cy, w, h = dets[q]
        box = [(cx - w / 2) * width, (cy - h / 2) * height, (cx + w / 2) * width, (cy + h / 2) * height]
        print(f"  {classes.get(str(int(scores[q].argmax())), scores[q].argmax()):<28} {score:.2f}  {np.round(box).astype(int).tolist()}")
    print("\nThe two lists should show the same classes and roughly the same boxes.")
    print("If class names are shifted by one, tell Claude: the class-index mapping needs an offset.")


if __name__ == "__main__":
    main()
