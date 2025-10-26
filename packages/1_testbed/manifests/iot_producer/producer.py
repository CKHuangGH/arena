from kafka import KafkaProducer
import json
import time

producer = KafkaProducer(
    bootstrap_servers='kafka.default.svc.cluster.local:9092',
    value_serializer=lambda v: json.dumps(v).encode('utf-8')
)

while True:
    data = {
        "sensor": "temperature",
        "value": 22.5,
        "unit": "C",
        "timestamp": time.time()
    }
    producer.send('test', value=data)
    print(f"Sent: {data}")
    time.sleep(0.1)