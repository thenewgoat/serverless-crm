First checkpoint: 6f24288 (no DB, working api + lambda)


To Remove in following order for manual teardown:

### Search API Gateway
aws_apigatewayv2_api.crm_api
aws_apigatewayv2_stage.default
aws_apigatewayv2_integration.clients
aws_apigatewayv2_integration.accounts
aws_apigatewayv2_route.*

### Search Lambda
aws_lambda_permission.allow_clients
aws_lambda_permission.allow_accounts
aws_lambda_function.clients
aws_lambda_function.accounts

###### Take note of logs

### 
aws_secretsmanager_secret.db_secret
aws_secretsmanager_secret_version.db_secret_ver
module.aurora

### Search Security Group
aws_security_group.lambda
aws_security_group.db

### Search IAM > Roles
aws_iam_role.lambda_exec
aws_iam_role_policy_attachment.lambda_logs
aws_iam_policy.lambda_db_policy
aws_iam_role_policy_attachment.lambda_db_attach

### Search VPC
module.vpc