
# Azure Sentinel Setup in Terraform

Deployment for Azure Sentinel via Terraform

Well for now it is just a LAW, the plan is to upgrade to Sentinel

### Custom tables

Use the script `createLogDeclaration.sh` to generate a table declaration for a custom log.

Example use:

```sh
./createLogDeclaration.sh "TimeGenerated, Computer, Message"
```

Output:

```json
[
    {
        "name": "TimeGenerated",
        "type": "enter_type",
        "desription": "enter_description"
    },
    {
        "name": "Computer",
        "type": "enter_type",
        "desription": "enter_description"
    },
    {
        "name": "Message",
        "type": "enter_type",
        "desription": "enter_description"
    }
]
```

**Custom table for Unifi Firewall logs**

UnifiLogs_CL

UnifiFirewallLogs_CL


### TODO

- Change to a Sentinel workspace
- Create some KQL queries
- Fix a Go program for logging and create a linux service for it
- Fix a pipeline for deployment
- Move DCR to separate file, and try to make it less anoying to work with