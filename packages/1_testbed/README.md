# Pandora Testbed – Kubernetes-Based IoT–Edge–Cloud Simulation

Welcome to the **Pandora Testbed**, a fully containerized local Kubernetes environment using **Kind (Kubernetes-in-Docker)**. This testbed simulates an industrial data flow pipeline involving **IoT**, **Edge**, and **Cloud** components — each isolated as a Kubernetes node with configurable CPU, memory, and network conditions.

Ideal for development, testing, and integration of streaming pipelines, message brokers, and inference models — all without needing cloud access or prior Kubernetes knowledge.

---

## 🚀 Features

*  Multi-node Kubernetes cluster (IoT, Edge, Cloud)
*  Fine-grained CPU/Memory resource constraints per node
*  Optional simulated latency & bandwidth constraints
*  Built-in monitoring with Kubernetes Dashboard
*  Secure, local-only execution — no internet required after setup
*  Works on **macOS** and **Windows**

---

## 📦 Requirements

 [Docker Desktop](https://www.docker.com/products/docker-desktop) 


---

## 🛠 Quick Start

### 🍏 macOS / Linux

```bash
git clone ../pandora-testbed.git
cd pandora-testbed-kind/scripts
chmod +x setup.sh
./setup.sh
```

Optional: Launch the Kubernetes Dashboard

```bash
./dashboard.sh
```

---

### �� Windows

1. **Clone or download** the repository
2. Run the setup script:

```cmd
scripts\setup.bat
```

3. *(Optional)* Launch the Dashboard:

```cmd
scripts\dashboard.bat
```

---

## 🧱 Cluster Architecture

This testbed creates a simulated environment with multiple nodes, each acting like a separate machine:

| Node Name | Role          | Function Example                   | Specs (Defined in `nodes.json`) |
| --------- | ------------- | ---------------------------------- | ------------------------------- |
| `cloud`   | Worker1       | Elasticsearch, Databases           | 1 CPU, 1Gi RAM                  |
| `iot`     | Worker        | Simulated Sensors, Data Generators | 1 CPU, 1Gi RAM                  |
| *(More)*  | Add your own  | Kafka, Logstash, Model Inference   | —                               |

All nodes are defined in:

```
scripts/nodes.json
```

---

## 📂 Repository Structure

```
Pandora-Testbed-Kind/
├── manifests/
│ ├── 01-namespaces/ # Kubernetes namespaces
│ ├── 02-secrets-and-configs/ # ConfigMaps, Secrets, etc.
│ ├── 03-core-infrastructure/ # Core services like Kafka & Zookeeper
│ ├── 04-data-platform/ # Elasticsearch manifests
│ ├── 05-pipeline-components/ # IoT Producer, Logstash, Kafka components
│ └── 06-networking/ # Network policies and chaos mesh configs
├── scripts/
│ ├── setup.sh # Complete setup for macOS/Linux
│ ├── setup.bat # Complete setup for Windows
│ ├── dashboard.sh # Kubernetes Dashboard launch script (macOS)
│ ├── dashboard.bat # Kubernetes Dashboard launch script (Windows)
| |── network_chaos.bat #instalation network chaos mesh
| |── network_chaos.sh #instalation network chaos mesh
│ ├── nodes.json # Node resource definitions
| |── cleanup.bat # cleanup cluster 
│ ├── cleanup.sh # cleanup cluster 
│ └── kind-cluster-template.json # Base Kind cluster config
```

---

## 📊 Dashboard Access

The setup script deploys a preconfigured Kubernetes Dashboard.

* After launch, a login token will be displayed
* Open your browser to [https://localhost:8443](https://localhost:8443)

Reopen later with:

```bash
kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard-kong-proxy 8443:443
kubectl -n kubernetes-dashboard create token dashboard-admin
```

---

## 💻 Deploying Your Modules

Partners can integrate their components using:

1. **Dockerize** their application
2. Create a **Kubernetes YAML** defining:

   * Image, container ports
   * CPU/Memory limits
   * Namespace (`iot`, `edge`, or `cloud`)
   * Nodes  (`IoT`, `Edge`, or `Cloud`)

3. Create ConfigMap and/or Secrets (optional):

Example ConfigMap:

```yaml
apiVersion: v1                        # API version used for core resources like ConfigMap
kind: ConfigMap                       # Declares this resource as a ConfigMap
metadata:
  name: my-app-config                 # Unique name for the config map
  namespace: my-namespace             # Namespace where this config applies
data:                                 # Key-value pairs for non-sensitive configs
  url: <service-name>.<namespace>.svc.cluster.local      # Example of a configuration entry (e.g., API endpoint)
  log_level: debug                    # Another common config: sets verbosity level in app
```
Example Secret:

```yaml
apiVersion: v1                        # Core API version
kind: Secret                          # Declares a Kubernetes Secret
metadata:
  name: my-app-secret                 # Name of the secret
  namespace: my-namespace             # Secret will be accessible in this namespace
type: Opaque                          # Default type for custom secrets
data:                                 # Data is base64 encoded (not encrypted!)
  username: <base64-encoded-value>    # Use: echo -n 'myuser' | base64
  password: <base64-encoded-value>    # Use: echo -n 'mypassword' | base64
```
4. Create Deployment YAML:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: edge                      # Change to: iot / edge / cloud
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      nodeSelector:
        testbed-role: Edge             # Change to: IoT / Cloud if needed
      containers:
      - name: my-container
        image: mydocker/image:tag      # Replace with your actual image name
        ports:
        - containerPort: 8080          # Port exposed by the container
        env:
        - name: APP_URL                # Example env from ConfigMap
          valueFrom:
            configMapKeyRef:
              name: my-app-config
              key: url
        - name: LOG_LEVEL              # Another example env from ConfigMap
          valueFrom:
            configMapKeyRef:
              name: my-app-config
              key: log_level
        - name: APP_USERNAME           # Secret reference for username
          valueFrom:
            secretKeyRef:
              name: my-app-secret
              key: username
        - name: APP_PASSWORD           # Secret reference for password
          valueFrom:
            secretKeyRef:
              name: my-app-secret
              key: password
        resources:                     # Optional
          requests:
            cpu: "250m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"

```

5. Create a Service (expose your app) :
Internal:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-service                 # Service name
  namespace: my-namespace              # Must match Deployment namespace
spec:
  selector:
    app: my-app                        # Links this service to Pods with this label
  ports:
    - protocol: TCP                    # Network protocol
      port: 80                         # Port exposed by the service inside the cluster
      targetPort: 8080                 # Port on the container (from Deployment)
```
External:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-service
  namespace: my-namespace
spec:
  selector:
    app: my-app                        # Connects to the right Pods
  type: NodePort                   # Exposes service externally via cloud provider
  ports:
    - protocol: TCP
      port: 80                         # Public-facing port
      targetPort: 8080                 # Port used by the container
      nodePort: 30080                  # (If using NodePort) Must be between 30000–32767
```
you can also port forward:

kubectl -n <namespace> port-forward svc/<service-name> <local-port>:<service-port>


6. Apply all YAMLs:

```bash
kubectl apply -f path/to/deployment.yaml
kubectl apply -f path/to/service.yaml
```

7. (Optional) Port forward for local testing:

```bash
kubectl port-forward svc/my-app-service 8080:80 -n my-app
```

---

## 🚩 Troubleshooting

* **Docker not running?** Make sure Docker Desktop is active
* **Cluster already exists?** Use `kind delete cluster --name pandora-testbed`
* **No Helm?** Use `brew install helm` or let script auto-install


---

## 🌀 Chaos Mesh Installation & Network Simulation

To enhance resilience testing within the Pandora Testbed, **Chaos Mesh** is employed for injecting controlled faults and simulating network disruptions across the IoT–Edge–Cloud pipeline.

### 🚀 Installing Chaos Mesh

Simply run the provided installation script:

```bash
./network_chaos.sh
```
This deploys Chaos Mesh into the dedicated chaos-mesh namespace in your Kubernetes cluster.

🔍 Verify Chaos Mesh Deployment
After installation, ensure all Chaos Mesh pods are fully running with:

```bash
kubectl get pods --namespace chaos-mesh -l app.kubernetes.io/instance=chaos-mesh
```
Note: Wait until all pods show STATUS as Running before proceeding.

⚙️ Apply Network Policies and Chaos Experiments
Once Chaos Mesh is confirmed operational, apply the network simulation manifests to enable fault injection and network constraints such as latency and bandwidth throttling:

```bash
kubectl apply -f manifests/06-networking/
```
This step configures the cluster to emulate realistic network conditions, essential for thorough testing of your IoT-to-Cloud data pipeline.


📡 Check Network Chaos Status
To inspect the status and details of a specific network chaos experiment, for example the delay between IoT and Cloud nodes, use:

```bash
kubectl describe networkchaos delay-iot-to-cloud -n iot
```



## 📌 Notes

* Cluster is local only, runs entirely in Docker
* Internet required **only during first-time setup**
* You can modify node specs by editing `nodes.json`

---









