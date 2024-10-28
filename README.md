# Flying K8s

![It's here!](image.png)

Promo : https://flyingk8s.milagrofrost.com/flyingk8s.mp3

Flying K8s is a Kubernetes setup that collects metrics for pods and nodes in a cluster and uploads them to Cloudflare R2 using the S3 API. The setup consists of two containers: a metrics collector and an AWS uploader. The metrics collector uses `kubectl` to gather metrics for pods and nodes, then writes them to a JSON file every minute. The AWS uploader uses `aws-cli` to upload the JSON file to Cloudflare R2 using the S3 API every minute.

After that, you can then use the metrics to create visualizations using Flying Toasters! https://github.com/milagrofrost/Flight-of-the-Toasters.  Just make sure to update the remoteDataUrl in the default.json file to point to the correct location of the JSON file (in the Flight of the Toasters deployment). 

## Demoooooooo

- https://flyingk8s.milagrofrost.com/
  - The minute-by-minute metrics are provided by the deployment detailed in this repo.  
  - And the flying toaster visualizations are provided by the Flight of the Toasters deployment.
- https://flyingk8s.milagrofrost.com/?configFile=k8s-demo
  - Showing off the sad toasts and toasters. 

## Deployment

This guide explains how to deploy the FlyingK8s setup in the `flying-k8s` namespace. The deployment consists of two containers:
- **Metrics Collector**: Uses `kubectl` to gather metrics for pods and nodes, then writes them to a JSON file every minute.
- **AWS Uploader**: Uses `aws-cli` to upload the JSON file to Cloudflare R2 using the S3 API every minute.

## Steps

1. **Create the Namespace**: 
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: flying-k8s
```

2. **Create a ConfigMap for the `flyingk8s.sh` Script**:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: flyingk8s-script
  namespace: flying-k8s
data:
  flyingk8s.sh: |
    #!/bin/bash

    # Set the timezone in environment variable
    # timezone=${TIMEZONE:-"UTC"}

    #########################
    #   It's Nodey time!    #
    #########################

    echo "Getting the top nodes in the cluster..."

    # Get the raw output of `kubectl top nodes`
    nodes_raw_output=$(kubectl top nodes)

    # Initialize JSON array for nodes
    nodes_json_output="[]"

    # Skip the header row and iterate through each line of `kubectl top nodes` output
    while IFS= read -r line; do
      if [[ $line != NAME* ]]; then
        echo $line

        # Parse the node name, CPU usage, and memory usage from each line
        node_name=$(echo $line | awk '{print $1}')
        cpu_usage=$(echo $line | awk '{print $3}' | sed 's/%//')   # Remove the '%' 
        memory_usage=$(echo $line | awk '{print $5}' | sed 's/%//')  # Remove the '%'

        # if cpuUsage is "<unknown>", set it to 4040404 and memoryUsage to 1
        if [[ $cpu_usage == "<unknown>" ]]; then
          cpu_usage="4040404"
          memory_usage=".01"
        else
          # add a leading zero to the cpu usage if it is less than 10, else just add a decimal point
          if [[ $cpu_usage -lt 10 ]]; then
            cpu_usage=".0$cpu_usage"
          else
            cpu_usage=".$cpu_usage"
          fi
          # add a leading zero to the memory usage if it is less than 10, else just add a decimal point
          if [[ $memory_usage -lt 10 ]]; then
            memory_usage=".0$memory_usage"
          else
            memory_usage=".$memory_usage"
          fi
        fi

        echo "Node: $node_name, CPU: $cpu_usage, Memory: $memory_usage"

        # Append the parsed data into a JSON array using jq
        nodes_json_output=$(echo "$nodes_json_output" | jq --arg node_name "$node_name" --arg cpu_usage "$cpu_usage" --arg memory_usage "$memory_usage" \
        '. + [{"name": $node_name, "cpuUsage": $cpu_usage, "memoryUsage": $memory_usage}]')
      fi
    done <<< "$nodes_raw_output"


    #########################
    #   It's Poddy time!    #
    #########################

    echo "Getting the top pods in the cluster..."

    # Get the raw output of `kubectl top pods`
    pods_raw_output=$(kubectl top pods --all-namespaces)

    # Initialize JSON array for pods
    pods_json_output="[]"

    # Skip the header row and iterate through each line of `kubectl top pods` output
    while IFS= read -r line; do
      if [[ $line != NAMESPACE* ]]; then
        # Parse the namespace, pod name, CPU usage, and memory usage from each line
        namespace=$(echo $line | awk '{print $1}')
        pod_name=$(echo $line | awk '{print $2}')
        cpu_usage=$(echo $line | awk '{print $3}' | sed 's/m//')   # Remove the 'm' 
        memory_usage=$(echo $line | awk '{print $4}' | sed 's/Mi//')  # Remove the 'Mi' for MiB

        # Append the parsed data into a JSON array using jq
        pods_json_output=$(echo "$pods_json_output" | jq --arg namespace "$namespace" --arg pod_name "$pod_name" --arg cpu_usage "$cpu_usage" --arg memory_usage "$memory_usage" \
        '. + [{"namespace": $namespace, "name": $pod_name, "cpuUsage": $cpu_usage, "memoryUsage": $memory_usage}]')
      fi
    done <<< "$pods_raw_output"

    # Look for pods that are not running and append custom values (CPU 4040404, Memory 1)
    not_ready_pods=$(kubectl get pods --all-namespaces -o json | jq '[.items[] | select(.status.phase != "Running") | {namespace: .metadata.namespace, name: .metadata.name, cpuUsage: "4040404", memoryUsage: "1"}]')

    # Ensure both pods_json_output and not_ready_pods are arrays before merging
    pods_json_output=$(jq -s '.[0] + .[1]' <(echo "$pods_json_output") <(echo "$not_ready_pods"))


    ######################
    #   It's timey time! #
    ######################

    # Get the current timestamp with time zone suffix
    timestamp=$(TZ=$timezone date +"%Y-%m-%dT%H:%M:%S%z")

    # Output the final JSON to file
    echo "{\"timestamp\":\"$timestamp\",\"nodes\":$nodes_json_output,\"pods\":$pods_json_output}" > /data/flyingk8s.json

```

3. **Create a Secret for AWS Credentials**:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: aws-credentials
  namespace: flying-k8s
type: Opaque
data:
  ACCOUNT_ID: #<base64-encoded-account-id>
  AWS_ACCESS_KEY_ID: #<base64-encoded-access-key-id>
  AWS_SECRET_ACCESS_KEY: #<base64-encoded-secret-key>
```

4. **Create the Service Account**:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flyingk8s-sa
  namespace: flying-k8s
```

5. **Create RBAC Role and RoleBinding**:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: flying-k8s
  name: flyingk8s-metrics-role
rules:
- apiGroups: [""]
  resources: ["pods", "nodes"]
  verbs: ["list"]
- apiGroups: ["metrics.k8s.io"]
  resources: ["pods", "nodes"]
  verbs: ["get", "list"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: flyingk8s-metrics-rolebinding
  namespace: flying-k8s
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: flyingk8s-metrics-role
subjects:
- kind: ServiceAccount
  name: flyingk8s-sa
  namespace: flying-k8s
```

6. **Create the Deployment**:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flyingk8s-deployment
  namespace: flying-k8s
spec:
  replicas: 1
  selector:
    matchLabels:
      app: flyingk8s
  template:
    metadata:
      labels:
        app: flyingk8s
    spec:
      serviceAccountName: flyingk8s-sa
      containers:
      - name: metrics-collector
        image: bitnami/kubectl:latest
        command: ["/bin/bash", "-c", "while true; do /data/flyingk8s.sh; sleep 60; done"]
        env:
          - name: timezone
            value: "US/Eastern"
        volumeMounts:
          - name: shared-data
            mountPath: /data
          - name: script-volume
            mountPath: /data/flyingk8s.sh
            subPath: flyingk8s.sh
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi

      - name: aws-uploader
        image: amazon/aws-cli:2.11.9
        command: ["/bin/sh", "-c", "while true; do aws s3api put-object --bucket $BUCKET_NAME --key flyingk8s.json --body /data/flyingk8s.json --endpoint-url $R2_ACCOUNT_ID_URL; sleep 60; done"]
        env:
          - name: BUCKET_NAME
            value: "frostbit-flying-k8s"
          - name: R2_ACCOUNT_ID_URL
            valueFrom:
              secretKeyRef:
                name: aws-credentials
                key: ACCOUNT_ID
          - name: AWS_ACCESS_KEY_ID
            valueFrom:
              secretKeyRef:
                name: aws-credentials
                key: AWS_ACCESS_KEY_ID
          - name: AWS_SECRET_ACCESS_KEY
            valueFrom:
              secretKeyRef:
                name: aws-credentials
                key: AWS_SECRET_ACCESS_KEY
        volumeMounts:
          - name: shared-data
            mountPath: /data
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi

      volumes:
      - name: shared-data
        emptyDir: {}
      - name: script-volume
        configMap:
          name: flyingk8s-script
```

## Apply the Configuration

1. **Apply the ConfigMap**:
   ```bash
   kubectl apply -f configmap.yaml
   ```

2. **Apply the Secret**:
   ```bash
   kubectl apply -f secret.yaml
   ```

3. **Create the Service Account**:
   ```bash
   kubectl apply -f serviceaccount.yaml
   ```

4. **Apply the RBAC Configuration**:
   ```bash
   kubectl apply -f rbac.yaml
   ```

5. **Apply the Deployment**:
   ```bash
   kubectl apply -f deployment.yaml
   ```