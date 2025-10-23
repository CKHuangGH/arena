# IoT → Kafka → Logstash → Elasticsearch Pipeline with Chaos Mesh

This guide explains how to deploy, test, and measure the performance of a complete data pipeline using **IoT producers**, **Kafka**, **Logstash**, and **Elasticsearch**, and how to evaluate its resilience and throughput under **Chaos Mesh network experiments** (e.g., latency injection).

---

## 1. Apply Kubernetes Manifests

Apply all Kubernetes manifests to deploy the components:


---

## 2. Verify All Pods Are Running

Check that all components are deployed and running correctly:

```bash
kubectl get pods -A
```

Expected pods (example):
```
default              iot-producer-xxxxxx             Running
default              kafka-xxxxx                     Running
default              zookeeper-xxxxx                 Running
default              logstash-xxxxx                  Running
default              elasticsearch-xxxxx             Running
```

---

## 3. Check Logstash Logs

You can confirm data flow from Kafka to Elasticsearch using:

```bash
kubectl logs -f deploy/logstash
```

If everything is configured properly, you should see Logstash consuming from the Kafka topic and indexing into Elasticsearch.  
Example log output:
```
Successfully consumed event from Kafka topic test
Indexed document into Elasticsearch index test
```

---

## 4. Access Elasticsearch (via Port Forward)

Expose Elasticsearch locally:

```bash
kubectl port-forward svc/elastic-service 9200:9200
```

Then, verify it’s running:

```bash
curl -u elastic:changeme "http://localhost:9200/_cluster/health?pretty"
```

Expected output:
```json
{
  "status" : "green",
  "number_of_nodes" : 1,
  "active_shards_percent_as_number" : 100.0
}
```

---

## 5. Install and Configure Chaos Mesh

Follow the official Chaos Mesh installation guide for your cluster:

[Chaos Mesh Installation Docs][https://chaos-mesh.org/docs/production-installation-using-helm/]

Once installed, verify the components:

```bash
kubectl get pods -n chaos-mesh
```

You should see:
```
chaos-controller-manager-xxxxx   Running
chaos-daemon-xxxxx               Running
chaos-dashboard-xxxxx            Running
```

Optionally, access the Chaos Mesh Dashboard (via port-forward):

```bash
kubectl port-forward -n chaos-mesh svc/chaos-dashboard 2333:2333
```

Open: [http://localhost:2333](http://localhost:2333)

---

## 6. Run the Throughput Test (Before Chaos)

Use the provided **Python throughput monitoring script** to measure Elasticsearch ingestion performance:

It will:
- Query Elasticsearch every few seconds
- Record indexed document count and throughput
- Save results in `es_throughput_10min.csv`
- Display a live plot

This run serves as your **baseline** (normal system performance).

---

## 7. Apply Chaos Mesh Delay Experiment

Example: inject 10s latency from IoT Producer to Kafka

Check its status:
```bash
kubectl get networkchaos -n chaos-mesh
```

---

## 8. Run the Throughput Test (After Chaos)

Run the same script again **while the Chaos experiment is active**:

```bash
python3 es_throughput_monitor.py
```

Then compare the new CSV file’s **average throughput** to the baseline.

You should observe:
- Lower document ingestion rate during Chaos (network latency impact)
- Recovery to baseline afterward

---

## 9. Analyze Results

Use the CSV data or graphs to compare performance:

| Experiment | Average Throughput (docs/s) | Observations |
|-------------|-----------------------------|---------------|
| Normal (no chaos) | 0.56 | Baseline ingestion rate |
| +10s latency | 0.30 | Delay slows down Kafka → Logstash → ES pipeline |
| Chaos removed | 0.55 | System recovered normally |

---


---

##  Summary

 You now have:
- A running **IoT → Kafka → Logstash → Elasticsearch** pipeline  
- Automated throughput monitoring  
- Chaos Mesh experiments to test network resilience  
- Quantifiable results to show system performance degradation and recovery  


[https://chaos-mesh.org/docs/production-installation-using-helm/]: https://chaos-mesh.org/docs/production-installation-using-helm/