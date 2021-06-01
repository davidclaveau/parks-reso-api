terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
   region = "ca-central-1"
}

// Auto pack lambda function.
data "archive_file" "readParkZip" {
    type        = "zip"
    source_dir  = "../readPark"
    output_path = "readPark.zip"
}

// Deploys the lambda via the zip above
resource "aws_lambda_function" "readParkLambda" {
   function_name = "readPark"
   filename = "readPark.zip"
   source_code_hash = "${data.archive_file.readParkZip.output_base64sha256}"

#    This method is for deploying things outside of TF.
#    s3_bucket = var.s3_bucket
#    s3_key    = "v1.0.0/readPark.zip"

   handler = "index.handler"
   runtime = "nodejs12.x"

   role = aws_iam_role.readRole.arn
}

resource "aws_api_gateway_rest_api" "apiLambda" {
  name        = "ParksDayUsePassAPI"
  description = "BC Parks DUP API"
}

resource "aws_api_gateway_resource" "readResource" {
  rest_api_id = aws_api_gateway_rest_api.apiLambda.id
  parent_id   = aws_api_gateway_rest_api.apiLambda.root_resource_id
  path_part   = "park"
}

// Defines the HTTP GET /park API
resource "aws_api_gateway_method" "readMethod" {
   rest_api_id   = aws_api_gateway_rest_api.apiLambda.id
   resource_id   = aws_api_gateway_resource.readResource.id
   http_method   = "GET"
   authorization = "NONE"
}

// Integrates the APIG to Lambda via POST method
resource "aws_api_gateway_integration" "readIntegration" {
   rest_api_id = aws_api_gateway_rest_api.apiLambda.id
   resource_id = aws_api_gateway_resource.readResource.id
   http_method = aws_api_gateway_method.readMethod.http_method

   integration_http_method = "POST"
   type                    = "AWS_PROXY"
   uri                     = aws_lambda_function.readParkLambda.invoke_arn
}

resource "aws_api_gateway_deployment" "apideploy" {
   depends_on = [ aws_api_gateway_integration.readIntegration]

   rest_api_id = aws_api_gateway_rest_api.apiLambda.id

   // TODO: Change this from prod to version??
   stage_name  = "Prod"
}

resource "aws_lambda_permission" "readPermission" {
   statement_id  = "AllowParksDayUsePassAPIInvoke"
   action        = "lambda:InvokeFunction"
   function_name = aws_lambda_function.readParkLambda.function_name
   principal     = "apigateway.amazonaws.com"
   source_arn = "${aws_api_gateway_rest_api.apiLambda.execution_arn}/*/*/*"
}

// Tells us what our api endpoint is in the CLI
output "base_url" {
  value = aws_api_gateway_deployment.apideploy.invoke_url
}

resource "aws_iam_policy" "lambda_logging" {
  name        = "lambda_logging"
  path        = "/"
  description = "IAM policy for logging from a lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.readRole.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

resource "aws_api_gateway_account" "DUPAPIGateway" {
  cloudwatch_role_arn = aws_iam_role.cloudwatch.arn
}

resource "aws_iam_role" "cloudwatch" {
  name = "api_gateway_cloudwatch_global"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "cloudwatch" {
  name = "default"
  role = aws_iam_role.cloudwatch.id

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams",
                "logs:PutLogEvents",
                "logs:GetLogEvents",
                "logs:FilterLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}