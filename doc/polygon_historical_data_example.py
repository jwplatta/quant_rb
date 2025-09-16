import boto3
from botocore.config import Config

# Initialize a session using your credentials
session = boto3.Session(
  aws_access_key_id='b3b89424-7959-4c9b-98f9-e08604fb141e',
  aws_secret_access_key='qEm8x8h7rikIXHQJwsVEUDj5B6IM6XqA',
)

# Create a client with your session and specify the endpoint
s3 = session.client(
  's3',
  endpoint_url='https://files.polygon.io',
  config=Config(signature_version='s3v4'),
)

# Specify the bucket name
bucket_name = 'flatfiles'

# Specify the S3 object key name
object_key = 'flatfiles/us_options_opra/minute_aggs_v1/2025/09/2025-09-12.csv.gz'

# Remove the bucket name (e.g. 'flatfiles/') prefix if present in object_key
if object_key.startswith(bucket_name + '/'):
  object_key = object_key[len(bucket_name + '/'):]

# Specify the local file name and path to save the downloaded file
local_file_name = object_key.split('/')[-1]  # e.g., '2025-06-12.csv.gz'
local_file_path = './' + local_file_name

# Print the file being downloaded
print(f"Downloading file '{object_key}' from bucket '{bucket_name}'...")

# Download the file
s3.download_file(bucket_name, object_key, local_file_path)