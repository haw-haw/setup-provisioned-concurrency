# Setup Provisioned Concurrency GitHub Action

This GitHub Action sets up and cleans up provisioned concurrency for a specified AWS Lambda function. It automatically publishes a new version of the Lambda function, sets up provisioned concurrency for that version, and deletes older versions along with their provisioned concurrency configurations.

## Prerequisites

- The AWS Lambda function must already exist.
- AWS credentials must be configured before running this action. 
- We recommend using [`aws-actions/configure-aws-credentials`](https://github.com/aws-actions/configure-aws-credentials) for this.

## IAM Permissions

The AWS credentials used must have the following IAM permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "lambda:PublishVersion",
        "lambda:PutProvisionedConcurrencyConfig",
        "lambda:ListVersionsByFunction",
        "lambda:DeleteProvisionedConcurrencyConfig",
        "lambda:DeleteFunction"
      ],
      "Resource": "arn:aws:lambda:REGION:ACCOUNT_ID:function:FUNCTION_NAME"
    }
  ]
}

```

Replace `REGION`, `ACCOUNT_ID`, and `FUNCTION_NAME` with your AWS region, account ID, and the name of your Lambda function, respectively.

## Usage

Here's a sample workflow to demonstrate how to use this action:

```yaml
name: Setup Provisioned Concurrency

on:
  push:
    branches:
      - main

jobs:
  deploy-job:
    runs-on: ubuntu-latest

    outputs:
      FUNCTION_NAMES: ${{ steps.deploy-step.outputs.FUNCTION_NAMES }}
      API_ID: ${{ steps.deploy-step.outputs.API_ID }}
      STAGE_NAME: ${{ steps.deploy-step.outputs.STAGE_NAME }}

    steps:
    - name: Checkout code
      uses: actions/checkout@v3

    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v3
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: us-west-2

    - name: Deploy Chalice App
      id: deploy-step
      run: |
        cd my-app/
        DEPLOY_OUTPUT=$(chalice deploy --stage dev | tee /dev/fd/2)
        FUNCTION_NAMES=$(echo "$DEPLOY_OUTPUT" | grep ":function:" | awk -F":function:" '{printf("%s\"%s\"", (NR==1?"[":","), $2)} END {print "]"}' | jq -c |  tee /dev/fd/2)
        echo "FUNCTION_NAMES=${FUNCTION_NAMES}" >> "$GITHUB_OUTPUT"
        if [[ "${DEPLOY_OUTPUT}" =~ [Hh][Tt][Tt][Pp][Ss]://([A-Za-z0-9]+)\.execute-api\.[^.]+\.amazonaws\.com\/([^/]+)\/ ]]; then
          API_ID="${BASH_REMATCH[1]}"
          STAGE_NAME="${BASH_REMATCH[2]}"
          echo "API_ID=${API_ID}" >> "$GITHUB_OUTPUT"
          echo "STAGE_NAME=${STAGE_NAME}" >> "$GITHUB_OUTPUT"
        fi

  setup-provisioned-concurrency:
    needs: deploy-job
    runs-on: ubuntu-latest
    strategy:
      matrix:
        function-name: ${{ fromJson(needs.deploy-job.outputs.FUNCTION_NAMES) }}
    steps:
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-region: us-west-2
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

      - name: Setup Provisioned Concurrency
        uses: haw-haw/setup-provisioned-concurrency@v3
        with:
          function-name: "${{ matrix.function-name }}"
          provisioned-concurrency: 2
          api-id: "${{ needs.deploy-job.outputs.API_ID }}"
          stage-name: "${{ needs.deploy-job.outputs.STAGE_NAME }}"
```

Replace `your-github-username` with your GitHub username and `your-lambda-function-name` with the name of your Lambda function.

## Inputs

| Input                    | Description                                     | Required | Default |
|--------------------------|-------------------------------------------------|----------|---------|
| `function-name`          | The name of the AWS Lambda function.            | Yes      |         |
| `provisioned-concurrency`| The number of provisioned concurrency to set up.| Yes      |         |
| `api-id`                 | The id of the api                               | No       |         |
| `stage-name`             | The stage name when redeploy api                | No       | 'dev'   |

## Outputs

- `new-version`: The new version of the Lambda function that was published.
- `provisioned-concurrency`: The number of provisioned concurrency that was set up.
- `function-name-full`: The lambda function name with version if it exists.

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## License

[MIT](LICENSE)
