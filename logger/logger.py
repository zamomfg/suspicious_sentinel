import os
from datetime import datetime
from azure.identity import DefaultAzureCredential
from azure.monitor.ingestion import LogsIngestionClient
from azure.core.exceptions import HttpResponseError
import logging
import re
import argparse

def log_data(client, dcr_immutableid, stream_name, logs):
    
    try:
        upload = client.upload(rule_id=dcr_immutableid, stream_name=stream_name, logs=logs)
    except HttpResponseError as e:
        print(f"Upload failed: {e}")


def follow(thefile):

    thefile.seek(0, os.SEEK_END)
    
    while True:
        # read last line of file
        line = thefile.readline()
        if not line:
            time.sleep(0.1)
            continue

        yield line


def get_logging_client(endpoint_uri):
    credential = DefaultAzureCredential(logging_enable=True)
    client = LogsIngestionClient(endpoint=endpoint_uri, credential=credential, logging_enable=True)

    return client


if __name__ == '__main__':

    parser = argparse.ArgumentParser(description="A script to send logs to a Log analytics workspace")

    parser.add_argument("-d", "--dcr", type=str, help="Data Collection Rule Immutable Id", required=True)
    parser.add_argument("-f", "--file", type=str, help="Path to log file that will be sent to workspace", required=True)
    parser.add_argument("-e", "--endpoint", type=str, help="enpoint url to log the data to", required=True)
    parser.add_argument("-s", "--stream", type=str, help="Name of the stream to log to", required=True)
    parser.add_argument("-r", "--regex", type=str, help="Regex of filtering logs before sending to workspace, if there is a match then the logs will be sent")

    args = parser.parse_args()

    # logging.basicConfig(level=logging.DEBUG)

    # hostname = platform.node()

    client = get_logging_client(args.endpoint)
    
    logfile = open(args.file,"r")
    loglines = follow(logfile)

    for line in loglines:
        
        if re.match(args.regex, line):
            message = line.split()
            time_generated = message[0]
            computer = message[1]
            process = message[2]

            body = [
                {
                "TimeGenerated": time_generated,
                "Computer": computer,
                "Message": re.search(": (.*)", line).group(1)
                }
            ]

            print(body)
            log_data(client, args.dcr, args.stream, body)