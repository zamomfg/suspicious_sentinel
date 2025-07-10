package main

import (
	"bufio"
	"flag"
	"fmt"
	"io"
	"os"
	"regexp"
	"strings"

	"github.com/nxadm/tail"

	"context"
	"encoding/json"
	"log"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/monitor/ingestion/azlogs"
)

var LOG_TYPES = []string{"Custom", "Syslog"} // add syslog
var HOSTNAME string

type FlagStruct struct {
	file     string
	creds    string
	log_type string
	regex    string
	endpoint string
	stream   string
	log_id   string
}

func main() {

	var flags = parse_arguments()

	var creds azcore.TokenCredential

	if flags.creds == "" {
		creds = get_default_creds()
	} else {
		creds = get_client_secret_creds(flags.creds)
	}

	client, err := azlogs.NewClient(flags.endpoint, creds, nil)
	if err != nil {
		log.Fatalf("Failed to create ingestion client: %v", err)
	}

	// var err error
	HOSTNAME, _ = os.Hostname()
	// if err != nil {
	// 	fmt.Printf("Error: %v\n", err)
	// 	return
	// }

	// tail file
	t, err := tail.TailFile(flags.file, tail.Config{
		Follow:   true,
		Location: &tail.SeekInfo{Offset: 0, Whence: io.SeekEnd},
	})
	if err != nil {
		panic(err)
	}

	re := regexp.MustCompile(flags.regex)

	for line := range t.Lines {

		if re.MatchString(line.Text) {
			var log_data = log_to_format(flags.log_type, line.Text)
			upload_logs(client, flags.log_id, flags.stream, log_data)
		}
	}
}

func get_default_creds() *azidentity.DefaultAzureCredential {

	creds, err := azidentity.NewDefaultAzureCredential(nil)
	if err != nil {
		// log.Fatalf("Failed to obtain a credential: %v", err)
	}

	return creds
}

func get_client_secret_creds(file_path string) *azidentity.ClientSecretCredential {

	var tenantId, clientId, clientSecret string

	file, err := os.Open(file_path)
	if err != nil {
		panic(err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "AZURE_TENANT_ID=") {
			tenantId = strings.TrimPrefix(line, "AZURE_TENANT_ID=")
		} else if strings.HasPrefix(line, "AZURE_CLIENT_ID=") {
			clientId = strings.TrimPrefix(line, "AZURE_CLIENT_ID=")
		} else if strings.HasPrefix(line, "AZURE_CLIENT_SECRET=") {
			clientSecret = strings.TrimPrefix(line, "AZURE_CLIENT_SECRET=")
		}
	}

	if err := scanner.Err(); err != nil {
		panic(err)
	}

	creds, err := azidentity.NewClientSecretCredential(tenantId, clientId, clientSecret, nil)
	if err != nil {
		log.Fatalf("Failed to obtain a credential: %v", err)
	}

	return creds
}

// TODO make this and the function get_client_secret_creds() generic share the logic for collection conf values
func get_conf_from_file(file_path string, flags *FlagStruct) *FlagStruct {

	file, err := os.Open(file_path)
	if err != nil {
		panic(err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "FILE=") {
			flags.file = strings.TrimPrefix(line, "FILE=")
		} else if strings.HasPrefix(line, "LOG_TYPE=") {
			flags.log_type = strings.TrimPrefix(line, "LOG_TYPE=")
		} else if strings.HasPrefix(line, "REGEX=") {
			flags.regex = strings.TrimPrefix(line, "REGEX=")
		} else if strings.HasPrefix(line, "ENDPOINT=") {
			flags.endpoint = strings.TrimPrefix(line, "ENDPOINT=")
		} else if strings.HasPrefix(line, "STREAM=") {
			flags.stream = strings.TrimPrefix(line, "STREAM=")
		} else if strings.HasPrefix(line, "ID=") {
			flags.log_id = strings.TrimPrefix(line, "ID=")
		} else if strings.HasPrefix(line, "CREDS=") {
			flags.creds = strings.TrimPrefix(line, "CREDS=")
		}
	}

	if err := scanner.Err(); err != nil {
		panic(err)
	}

	return flags
}

func log_to_format(format string, line string) []byte {

	var logData []map[string]string

	if format == "Custom" {
		logData = []map[string]string{
			{
				"TimeGenerated": time.Now().Format(time.RFC3339),
				"Computer":      HOSTNAME,
				"Message":       line,
			},
		}
	}

	if format == "Syslog" {

		// this is based on the syntax of unifi logs, they are missing some parts of the syslog
		// group 1: datetime, group 2: computer, group 3: facility, group 4: message
		re := regexp.MustCompile(`^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2})`)
		match := re.FindStringSubmatch(line)

		logData = []map[string]string{
			{
				"TimeGenerated": match[1],
				"Message":       line,
			},
		}
	}

	logBytes, err := json.Marshal(logData)
	if err != nil {
		log.Fatalf("Failed to marshal log data: %v", err)
	}

	return logBytes
}

func upload_logs(client *azlogs.Client, logId string, streamName string, logData []byte) {

	_, err := client.Upload(context.TODO(), logId, streamName, logData, nil)
	if err != nil {
		// log.Fatalf("Failed to send logs: %v", err)
		log.Print("Failed to send logs: %v", err)
	}
}

func parse_arguments() FlagStruct {

	var flags FlagStruct
	var confFile string

	flag.StringVar(&confFile, "conf", "", "Path to conf file")
	flag.StringVar(&flags.file, "file", "", "Path to file")
	flag.StringVar(&flags.creds, "creds", "", "Path to file with Azure credentials")
	flag.StringVar(&flags.log_type, "log_type", "Custom", "Type of log file. Supported values are Custom, System, Security")
	flag.StringVar(&flags.regex, "regex", ".*", "Regex to filter the logs")
	flag.StringVar(&flags.endpoint, "endpoint", "", "Data collection endpoint url")
	flag.StringVar(&flags.stream, "stream", "", "Stream name")
	flag.StringVar(&flags.log_id, "id", "", "Immutable Id of DCR")

	flag.Parse()

	if confFile != "" {
		get_conf_from_file(confFile, &flags)
		// fmt.Printf("%+v\n", flags)
	}

	if flags.file == "" {
		fmt.Println("Error: -file is a required flag")
		flag.Usage()
		os.Exit(99)
	}

	// if flags.creds == "" {
	// 	fmt.Println("Error: -creds is a required flag")
	// 	flag.Usage()
	// 	os.Exit(1)
	// }

	// if flags.log_type == "" {
	// 	fmt.Println("Error: -log_type is a required flag")
	// 	flag.Usage()
	// 	os.Exit(1)
	// }

	if flags.regex == "" {
		flags.regex = ".*"
	}

	if flags.endpoint == "" {
		fmt.Println("Error: -Endpoint is a required flag")
		flag.Usage()
		os.Exit(98)
	}

	if flags.stream == "" {
		fmt.Println("Error: -Stream is a required flag")
		flag.Usage()
		os.Exit(97)
	}

	if flags.log_id == "" {
		fmt.Println("Error: -Id is a required flag")
		flag.Usage()
		os.Exit(96)
	}

	return flags

}
