#!/usr/bin/ruby
require 'time'
require 'socket'
require 'json'
server = TCPServer.new "9110"

# replace ruby location
# Replace with your rippled setup
# you can use some other port instead of 9110
rippled_base_cmd = "/usr/local/bin/rippled --conf /etc/opt/ripple/rippled.cfg"

DEFAULT_SERVER_INFO = {
  "result" => {
    "info" => {
      "peers" => 0,
      "server_state" => "disconnected",
      "load" => { "threads" => 0, "job_types" => [] },
      "last_close" => { "converge_time_s" => 0, "proposers" => 0 },
      "uptime" => 0,
      "peer_disconnects" => 0,
      "load_factor" => 0
    }
  }
}

DEFAULT_LEDGER_INFO = {
  "result" => {
    "ledger" => {
      "ledger_index" => 0,
      "close_time" => 0
    }
  }
}

# Method to parse JSON and return a default in case of failure
def parse_json(json_str, default)
  json_start = json_str.index('{')
  if json_start
    begin
      JSON.parse(json_str[json_start..-1])
    rescue JSON::ParserError, NoMethodError => e
      puts "Error: Failed to parse JSON. #{e.message}"
      default
    end
  else
    puts "Error: No valid JSON found."
    default
  end
end

while session = server.accept
  request = session.gets
  node_timestamp = Time.now.to_i

  # Run the rippled command and capture the output
  server_info = `#{rippled_base_cmd} server_info`
  ledger_validated = `#{rippled_base_cmd} ledger validated`

  if server_info.empty? || ledger_validated.empty?
    puts "Error: Failed to get data from rippled."
  end

  # Parse JSON for server info and ledger validated
  server_parsed_data = parse_json(server_info, DEFAULT_SERVER_INFO)
  ledger_validated_parsed_data = parse_json(ledger_validated, DEFAULT_LEDGER_INFO)

  # Init peers and index
  rippled_peers = server_parsed_data["result"]["info"]["peers"].to_i
  rippled_ledger_index = ledger_validated_parsed_data["result"]["ledger"]["ledger_index"].to_i

  # Setup proper timestamp
  rippled_ledger_index_time = ledger_validated_parsed_data["result"]["ledger"]["close_time"].to_i + 946684800

  # Check catching up status
  rippled_catching_up = ["full","validating","proposing"].include?(server_parsed_data["result"]["info"]["server_state"]) ? 0 : 1

  # Init Jobs
  rippled_jobs = server_parsed_data["result"]["info"]["load"]["job_types"]

  # If the ledger index is zero, output NaN to Prometheus instead of skipping
  if rippled_ledger_index == 0
    rippled_ledger_index_time = 0
    rippled_catching_up = 0
  end

  if !rippled_jobs.empty?
		rippled_job_values = Hash.new { |hash, key| hash[key] = {} }

	  # Now, update the hash with actual values if they exist in the response
	  rippled_jobs.each do |job|
	    job_type = job["job_type"]

	    # Only update the fields that exist in the response
	    rippled_job_values[job_type]["per_second"] = job["per_second"] if job.key?("per_second")
	    rippled_job_values[job_type]["peak_time"] = job["peak_time"] if job.key?("peak_time")
	    rippled_job_values[job_type]["in_progress"] = job["in_progress"] if job.key?("in_progress")
	    rippled_job_values[job_type]["avg_time"] = job["avg_time"] if job.key?("avg_time")
	  end
	end

  # Printing Session Values
  session.print "HTTP/1.1 200\n"
  session.print "Content-Type: text/plain\n"
  session.print "\n"
  session.print "#rippled exporter\n"

  session.print "# HELP The current Unix timestamp from the node (in seconds).\n"
  session.print "# TYPE node_timestamp counter\n"
  session.print "node_timestamp #{node_timestamp}\n"

  session.print "# HELP The index of the last fully validated ledger synced by the rippled server\n"
  session.print "# TYPE rippled_ledger_index counter\n"
  session.print "rippled_ledger_index #{rippled_ledger_index}\n"

  session.print "# HELP The Unix timestamp of the last synced ledger.\n"
  session.print "# TYPE rippled_ledger_index_time counter\n"
  session.print "rippled_ledger_index_time #{rippled_ledger_index_time}\n"

  session.print "# HELP A status indicator (0 or 1) showing whether the node is catching up with the network.\n"
  session.print "# TYPE rippled_catching_up gauge\n"
  session.print "rippled_catching_up #{rippled_catching_up}\n"

  session.print "# HELP The current number of peers connected to the rippled node.\n"
  session.print "# TYPE rippled_peers gauge\n"
  session.print "rippled_peers #{rippled_peers}\n"

  if !rippled_jobs.empty?
	  rippled_job_values.each do |job_type, metrics|
	    metrics.each do |metric_name, value|
	      # Generate the HELP line
	      session.print "# HELP rippled #{job_type} #{metric_name.gsub('_', ' ')}.\n"

	      # Define the metric name and type (gauge for all these types)
	      metric_type = "gauge"
	      session.print "# TYPE rippled_#{job_type}_#{metric_name} #{metric_type}\n"

	      # Print the metric with the current value (can be NaN)
	      session.print "rippled_#{job_type}_#{metric_name.downcase} #{value}\n"
	    end
	  end
	end

  session.print "# HELP The time it took for the network to reach consensus on the last ledger close.\n"
  session.print "# TYPE rippled_last_close_converge_times gauge\n"
  session.print "rippled_last_close_converge_times #{server_parsed_data["result"]["info"]["last_close"]["converge_time_s"].to_i}\n"

  session.print "# HELP The number of validators that participated in the consensus process during the last ledger close.\n"
  session.print "# TYPE rippled_last_close_proposers gauge\n"
  session.print "rippled_last_close_proposers #{server_parsed_data["result"]["info"]["last_close"]["proposers"].to_i}\n"

  session.print "# HELP rippled process threads.\n"
  session.print "# TYPE rippled_load_threads gauge\n"
  session.print "rippled_load_threads #{server_parsed_data["result"]["info"]["load"]["threads"].to_i}\n"

  session.print "# HELP rippled service uptime.\n"
  session.print "# TYPE rippled_service_uptime counter\n"
  session.print "rippled_service_uptime #{server_parsed_data["result"]["info"]["uptime"].to_i}\n"

  session.print "# HELP rippled number of times your rippled server has disconnected from peers in the Ripple network.\n"
  session.print "# TYPE rippled_peer_disconnects counter\n"
  session.print "rippled_peer_disconnects #{server_parsed_data["result"]["info"]["peer_disconnects"].to_i}\n"

  session.print "# HELP rippled load_factor load_factor = 1 (base), >1 higher-than-normal traffic or congestion, <1 rare low load.\n"
  session.print "# TYPE rippled_load_factor gauge\n"
  session.print "rippled_load_factor #{server_parsed_data["result"]["info"]["load_factor"].to_i}\n"

  session.close
end