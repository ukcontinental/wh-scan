# Proxy extraction task (held-out set)
Act as the vision model in the business-card pipeline. Follow system_prompt.txt (this directory) exactly; output must validate
against /home/user/wh-scan/CardImport/schema/extraction-api.schema.json (all properties present, null/[] when absent,
snake_case, schema_version 1). No OCR transcript is available — read the image only (you may crop/enlarge with PIL).
Write extractions/<photo_id>.json and check it parses.
STRICT RULES: never open anything under dataset_holdout/ except dataset_holdout/images/<your ids>.jpg; never open dataset/,
runs/*/run.json, runs/*/score.json, runs/proxy/, or other agents' extraction files.
