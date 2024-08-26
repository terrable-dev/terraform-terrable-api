mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/example-role"
    }
  }

  mock_resource "aws_lambda_permission" {
    defaults = {
      arn = "arn:aws:execute-api:us-east-1:123456789012:abcdef123/*/GET/test"
    }
  }

  mock_resource "aws_lambda_function" {
    defaults = {
      invoke_arn = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:123456789012:function:test-function/invocations"
    }
  }

  mock_resource "aws_apigatewayv2_api" {
    defaults = {
      execution_arn = "arn:aws:execute-api:us-east-1:123456789012:abcdef123"
    }
  }
}

variables {
  api_name = "test-api"
  handlers = {
    TestHandler : {
      source = "./tests/handler.js"
      http = {
        method = "GET"
        path   = "/"
      }
    }
  }
}

run "api_gateway_has_correct_name" {
  assert {
    condition     = aws_apigatewayv2_api.api_gateway.name == "test-api"
    error_message = "incorrect API Gateway name"
  }
}

run "default_stage_name" {
  assert {
    condition     = aws_apigatewayv2_stage.default.name == "$default"
    error_message = "default stage name not set"
  }
}

run "lambda_function_names" {
  assert {
    condition = alltrue([
      for key, handler in var.handlers :
      aws_lambda_function.handlers[key].function_name == format("%s-TestHandler", var.api_name)
    ])

    error_message = "expected cloudwatch log groups not created"
  }
}

run "cloudwatch_log_groups_created" {
  assert {
    condition = alltrue([
      for key, handler in var.handlers :
      aws_cloudwatch_log_group.lambda_log_groups[key].name == format("/aws/lambda/test-api-%s", key)
    ])

    error_message = "expected cloudwatch log groups not created"
  }
}

run "attach_lambda_role" {
  assert {
    condition = alltrue([
      for key, handler in var.handlers :
      aws_lambda_function.handlers[key].role == aws_iam_role.lambda_role.arn
    ])

    error_message = "lambda roles not attached"
  }
}

run "lambda_role_cloudwatch_attachment" {
  assert {
    condition     = aws_iam_role_policy_attachment.lambda_logs.policy_arn == "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    error_message = "lambda cloudwatch attachment missing basic execution policy"
  }

  assert {
    condition     = aws_iam_role_policy_attachment.lambda_logs.role == aws_iam_role.lambda_role.name
    error_message = "lambda cloudwatch attachment not attached to lambda role"
  }
}

run "all_routes_added" {
  assert {
    condition = alltrue([
      for key, handler in var.handlers :
      contains(keys(aws_apigatewayv2_route.lambda_routes), key) &&
      aws_apigatewayv2_route.lambda_routes[key].route_key == "${handler.http.method} ${handler.http.path}"
    ])

    error_message = "one or more routes have not been mapped"
  }

  assert {
    condition     = length(keys(aws_apigatewayv2_route.lambda_routes)) == length(keys(var.handlers))
    error_message = "one or more routes have not been mapped"
  }
}
