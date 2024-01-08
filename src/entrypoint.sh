#!/bin/bash

# Function to handle errors
handle_error() {
  echo "Error on line $1"
  exit 1
}

# Trap errors and call handle_error function
trap 'handle_error $LINENO' ERR

# Function to check if a command exists
command_exists() {
  command -v "$1" &> /dev/null
}

# Install AWS CLI if not already installed
install_aws_cli() {
  if ! command_exists aws; then
    echo "AWS CLI could not be found, installing..."
    pip install awscli
  else
    echo "AWS CLI is already installed."
  fi
}

# Publish a new version for Lambda function
publish_lambda_version() {
  echo "Publishing a new version for Lambda function: $INPUT_FUNCTION_NAME..."
  NEW_VERSION=$(aws lambda publish-version --function-name "$INPUT_FUNCTION_NAME" --query "Version" --output text)
  echo "Successfully published new version: $NEW_VERSION"

  echo "NEW_VERSION=$NEW_VERSION" >> "$GITHUB_ENV"
}

# Set up provisioned concurrency for the new version
setup_provisioned_concurrency() {
  echo "Setting up provisioned concurrency for version: $NEW_VERSION..."
  aws lambda put-provisioned-concurrency-config \
    --function-name "$INPUT_FUNCTION_NAME" \
    --qualifier "$NEW_VERSION" \
    --provisioned-concurrent-executions "$INPUT_PROVISIONED_CONCURRENCY"
  echo "Successfully set up provisioned concurrency for version: $NEW_VERSION"

  echo "PROVISIONED_CONCURRENCY=$INPUT_PROVISIONED_CONCURRENCY" >> "$GITHUB_ENV"
}

# Update API's resource
update_api_resource() {
  if [ -z "${INPUT_API_ID}" ]; then
    echo "No API ID provided, skipping API updating."
    return
  fi
  new_function_name_full="${INPUT_FUNCTION_NAME}:${NEW_VERSION}"
  echo "Updating API GateWay's API(id: ${INPUT_API_ID}) resource's backend"
  API_RESOURCE_IDS=$(aws apigateway get-resources \
    --rest-api-id "${INPUT_API_ID}" \
    --query 'items[].id' \
    --output text)

  for id in ${API_RESOURCE_IDS}
  do
    echo "==resource id: ${id}"
    METHODS=$(aws apigateway get-resources \
      --rest-api-id "${INPUT_API_ID}" \
      --query "items[?id=='${id}'].resourceMethods | [0] | keys(@)" \
      --output text)
    for method in ${METHODS}
    do
      echo "====method: ${method}"
      [[ "${method}" == 'OPTIONS' ]] && continue
      methodIntegration_uri=$(aws apigateway get-method \
        --rest-api-id "${INPUT_API_ID}" \
        --resource-id "${id}" \
        --http-method "${method}" \
        --query "methodIntegration.uri")
      [[ ${methodIntegration_uri} =~ ":function:" ]] || continue
      function_name_full=$(echo "${methodIntegration_uri}" | \
        awk -F":function:" '{print $2}' | \
        cut -d'/' -f1)
      [[ "${function_name_full}" == "${new_function_name_full}" ]] && continue
      function_name=$(echo "${function_name_full}" | \
        cut -d':' -f1)
      [[ "${function_name}" == "${INPUT_FUNCTION_NAME}" ]] || continue
      methodIntegration_uri_new=${methodIntegration_uri/$function_name_full/$new_function_name_full}
      aws apigateway update-integration \
        --rest-api-id "${INPUT_API_ID}" \
        --resource-id "${id}" \
        --http-method "${method}" \
        --patch-operations \
          op=replace,path='/uri',value="${methodIntegration_uri_new}" || \
        echo "Failed to update uri from ${methodIntegration_uri} to ${methodIntegration_uri_new}"
      echo "======replace \"${function_name_full}\" with \"${new_function_name_full}\" success."
    done
  done

  echo "NEW_FUNCTION_NAME_FULL=$new_function_name_full" >> "$GITHUB_ENV"
}

# Clean up older versions
cleanup_old_versions() {
  OLDER_VERSIONS=$(aws lambda list-versions-by-function \
    --function-name "${INPUT_FUNCTION_NAME}" \
    --query "Versions[?Version!='\$LATEST' && Version!='${NEW_VERSION}'].Version" \
    --output text)

  if [ -z "${OLDER_VERSIONS}" ]; then
    echo "No older versions found. Skipping deletion."
    return
  fi
  for OLD_VERSION in ${OLDER_VERSIONS}; do
    echo "Deleting provisioned concurrency for version: ${OLD_VERSION}..."
    aws lambda delete-provisioned-concurrency-config \
      --function-name "${INPUT_FUNCTION_NAME}" \
      --qualifier "${OLD_VERSION}" || echo "No provisioned concurrency to delete for version: $OLD_VERSION"

    echo "Deleting version: ${OLD_VERSION}..."
    aws lambda delete-function \
      --function-name "${INPUT_FUNCTION_NAME}" \
      --qualifier "${OLD_VERSION}" || echo "Failed to delete version: ${OLD_VERSION}"
  done
}

# Main script execution
main() {
  install_aws_cli
  publish_lambda_version
  setup_provisioned_concurrency
  update_api_resource
  cleanup_old_versions
}

# Execute the main function
main