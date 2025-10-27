from kafka import KafkaProducer
import json
import time

# === 固定設定 ===
TOPIC = "test"
PAYLOAD_SIZE = 10000     # 每筆 10 KB
INTERVAL = 0.005         # 每 0.005 秒發一筆 ≈ 200 msg/s
# 約 10 KB × 200 × 8 = 16 Mbps (baseline)
# =================

producer = KafkaProducer(
    bootstrap_servers='kafka.default.svc.cluster.local:9092',
    value_serializer=lambda v: json.dumps(v).encode('utf-8')
)

payload = "X" * PAYLOAD_SIZE
seq = 0

while True:
    seq += 1
    data = {
        "seq": seq,
        "sensor": "temperature",
        "value": 22.5,
        "unit": "C",
        "timestamp": time.time(),
        "blob": payload
    }
    producer.send(TOPIC, value=data)
    time.sleep(INTERVAL)
