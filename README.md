# Rippled Prometheus Exporter & Monitoring Setup

This repository provides an automated Prometheus exporter setup for monitoring the `rippled` node along with a Grafana dashboard for visualization and Prometheus alerting rules.

## Setup Overview

The setup includes:

- **Prometheus Scrape Configurations**: Automatic scrape configuration for discovering and scraping metrics from `rippled` nodes on AWS and GCP.
- **Prometheus Alerting Rules**: Custom alerts for monitoring `rippled` sync distance and node health.
- **Grafana Dashboard**: Pre-configured Grafana dashboard for visualizing key metrics of the `rippled` node.

## Prerequisites

- A working **Prometheus** instance configured to scrape `rippled` node metrics.
- **Grafana** instance to visualize the data.
- **rippled** node instances running and exporting metrics via the `rippled_exporter` (default port: 9110).

## Prometheus Scrape Configuration

The scrape configuration supports two sources for metric collection:

1. **AWS EC2 Instance Discovery**: The configuration dynamically scrapes `rippled` nodes running on AWS EC2. It uses EC2 tags to filter instances and only scrape those with the `rippled` tag.

    ```yaml
    - job_name: 'rippled'
      ec2_sd_configs:
        - region: "your-aws-region"
          filters:
            - name: "tag:Type"
              values:
                - "rippled"
            - name: "instance-state-name"
              values:
                - "running"
          port: 9110
          refresh_interval: "60s"
      relabel_configs:
        - source_labels: [__meta_ec2_tag_Type]
          target_label: type
        - source_labels: [__meta_ec2_tag_Project]
          target_label: project
        - source_labels: [__meta_ec2_tag_Name]
          target_label: name
        - source_labels: [__meta_ec2_instance_id]
          target_label: instance
        - source_labels: [__meta_ec2_region]
          target_label: cloud_region
        - source_labels: [__meta_ec2_availability_zone]
          target_label: cloud_zone
        - source_labels: [__meta_ec2_instance_type]
          target_label: instance_type
    ```
2. **GCP GCE Instance Discovery**: The configuration dynamically scrapes `rippled` nodes running on GCP GCE. It uses GCE tags to filter instances and only scrape those with the `rippled` tag.

	```yaml
	- job_name: 'rippled'
	  gce_sd_configs:
	    - project: "your-project-name"
	      zone: "your-gcp-zone"
	      #example filters matching your rippled instances
	      filter: '(status="RUNNING") AND (labels.type="rippled")'
	      refresh_interval: "60s" 
	      port: 9110
	  relabel_configs:
	    - source_labels: [__meta_gce_label_cloud_provider]
	      target_label: cloud_provider
	    - source_labels: [__meta_gce_label_cloud_zone]
	      target_label: cloud_zone
	    - source_labels: [__meta_gce_label_cloud_tier]
	      target_label: cloud_tier
	    - source_labels: [__meta_gce_label_cloud_service]
	      target_label: cloud_service
	    - source_labels: [__meta_gce_instance_name]
	      target_label: instance
	    - source_labels: [__meta_gce_label_project]
	      target_label: project
	    - source_labels: [__meta_gce_label_name]
	      target_label: name
	    - source_labels: [__meta_gce_label_type]
	      target_label: type

	```

3. **Static Configuration**: For nodes with static IPs or other fixed targets, use the static configuration.

    ```yaml
    - job_name: 'rippled'
      static_configs:
      - targets: ['your-rippled-domain-or-ip:9110']
        labels:
          node_name: 'rippled1'
          job: 'rippled'
          project: 'some_project'
          name: 'rippled'
          type: 'blockchain'
    ```

### Key Labels for Querying:
- **job**: `rippled`
- **project**: Specifies the project label (useful for multi-project setups).
- **node_name**: The name of the node instance.
- **type**: Set to `blockchain`.

## Prometheus Alerting Rule

This setup includes a custom alert rule that triggers if the sync distance between the last validated ledger and the current node timestamp exceeds 1800 seconds (30 minutes), which may indicate the node is lagging behind in syncing.

### Rule Example:

```yaml
groups:
- name: rippled
  rules:
  - alert: Rippled LargeSyncDistance
    expr: node_timestamp - rippled_ledger_index_time > 1800
    for: 10m
    labels:
      severity: warning
      type: blockchain
    annotations:
      summary: "Rippled last synced more than 30 minutes ago (instance {{ $labels.instance }})"
      description: "Rippled sync distance is VALUE = {{ $value }}\nLABELS = {{ $labels }}"
```

This rule checks if the difference between the `node_timestamp` and `rippled_ledger_index_time` is greater than 1800 seconds and triggers an alert if the condition persists for more than 10 minutes.

## Grafana Dashboard

### Features of the Dashboard:
- **Graphs for**:
  - Rippled Load
  - Process Factor
  - Peers
  - Service Data
  - Last Block Age (in seconds)
  - Job Timers (for various metrics such as `per_second`, `peak_time`, `in_progress`, `avg_time`)

- **Stats for**:
  - Service Uptime
  - Last Block Time
  - Last Block Index
  - Catching Up Status (whether the node is fully synced or lagging behind)

### Dashboard Installation:
1. Import the **Grafana Dashboard** JSON from the provided file `rippled-dashboard.json`.
2. The dashboard folder includes various graphs and panels to monitor the health and performance of the `rippled` node.
3. The dashboard folder also includes a demo PNG (`rippled-dashboard.png`) to show how the dashboard will look once set up.

### Sample Graphs:
- **Rippled Load**: Displays the load on the node.
- **Peers**: Shows the current number of connected peers.
- **Service Data**: Displays metrics related to the service uptime and other service-related metrics.
- **Job Timers**: Provides details on job performance such as the average time and jobs in progress.

## How to Use

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/your-repo/rippled-prometheus-exporter.git
   cd rippled-prometheus-exporter
   ```

2. **Configure Prometheus**:
   - Add the `rippled` scrape configuration (as shown above) to your Prometheus configuration (`prometheus.yml`).
   - Ensure the `rippled_exporter` is running on the nodes you wish to monitor.

3. **Set Up Alerts**:
   - Add the alerting rule (as shown above) to your Prometheus alerting configuration.

4. **Import Grafana Dashboard**:
   - Import the `rippled-dashboard.json` file into your Grafana instance.
   - Optionally, use the `rippled-dashboard.png` file to preview the dashboard layout.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
