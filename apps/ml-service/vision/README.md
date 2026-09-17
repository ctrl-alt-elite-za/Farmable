# Vision pipeline

Organise the private dataset as `data/<version>/{train,test}/images` with an
`image_sessions.csv` manifest containing `image,session_id` columns. Validate
the session split before training:

```bash
python apps/ml-service/vision/check_split.py --train data/v1/train/images --test data/v1/test/images --manifest data/v1/image_sessions.csv
```

`train.py` uses a fixed seed and requires a separately managed, pinned
Ultralytics/TFLite training environment (for example Colab). It writes a
versioned report and can export TFLite; it does not download data in CI.

Record real cabbage and tomato measurements in `weights/cabbage.csv` and
`weights/tomato.csv` with `diameter_cm,weight_g,date`, then run
`python apps/ml-service/vision/eval_weights.py apps/ml-service/vision/weights/cabbage.csv apps/ml-service/vision/weights/tomato.csv`.
Spinach is sold by bunch or kilogram and has no per-plant formula. Do not add
synthetic measurements to satisfy the minimum sample count.
