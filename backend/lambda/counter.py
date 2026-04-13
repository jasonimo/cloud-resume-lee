import json
import boto3
import os

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    response = table.update_item(
        Key={'id': 'visitors'},
        UpdateExpression='ADD visit_count :inc',
        ExpressionAttributeValues={':inc': 1},
        ReturnValues='UPDATED_NEW'
    )

    count = int(response['Attributes']['visit_count'])

    return {
        'statusCode': 200,
        'headers': {
            'Access-Control-Allow-Origin': 'https://lee-j.com',
            'Access-Control-Allow-Methods': 'GET',
        },
        'body': json.dumps({'count': count})
    }