# Crop labelling guide

This guide defines the labels used by the all-crop detector. Label only plots owned by, or made available to, the team. Do not upload the dataset to this repository: `apps/ml-service/vision/data/` is ignored and the source bucket must be private.

## Classes

| Class                | Label when                                                | Do not label                                    |
| -------------------- | --------------------------------------------------------- | ----------------------------------------------- |
| `plant`              | The visible plant or plant canopy                         | Soil, weeds, tools, or an empty row             |
| `crop_head_or_fruit` | A cabbage head or a visible tomato fruit                  | Leaves, stems, flowers, or spinach leaves       |
| `check_suggested`    | A visible hole, yellowing, or spot that should be checked | Shadows, glare, dust, or an uncertain occlusion |

Use one tight bounding box per visible instance. Include the whole visible cabbage head, tomato fruit, or plant canopy, but do not guess hidden parts. For `check_suggested`, draw the box around the visible symptom, not the whole plant.

## Capture and review

Capture at least 300 images of each of cabbage, tomato, and spinach across morning, midday, and overcast light, from 0.3–1.5 m. Record a stable `session_id` for each filming session. Review class names, box edges, and blurred faces/number plates before export.

Export YOLO labels as normalized `class_id x_center y_center width height` values. Keep source images and labels in the private bucket. Split by `session_id`, never by individual image; run `python apps/ml-service/vision/check_split.py` before training.

## Examples

The private dataset contains the actual photos; these examples describe the expected annotations:

- A cabbage plant with its head visible: `plant` around the canopy and `crop_head_or_fruit` around the head.
- A tomato plant with two visible tomatoes: one `plant` box and two fruit boxes.
- A spinach row: `plant` boxes around visible clumps; no fruit box.
- A yellow patch on a leaf: a small `check_suggested` box around the patch.
- A person or number plate: discard the frame or blur it before upload.

Record dataset, model, export, and train/test session versions with every run. Discard frames that cannot be made privacy-safe.
