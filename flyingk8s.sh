#!/bin/bash


# for testing not part of the actual deployment

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
