# Proxy extraction task
Act as the vision model in the business-card pipeline. Follow system_prompt.txt exactly; output must validate against
/home/user/wh-scan/CardImport/schema/extraction-api.schema.json (all properties present, null/[] when absent, snake_case).
No OCR transcript is available in this run — read the image only. Write extractions/<photo_id>.json and check it parses.
STRICT RULES: never open dataset/clean/, dataset/html/, dataset/ground_truth.json, dataset/README.md, runs/*/run.json,
or other agents' extraction files.
