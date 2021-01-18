require 'json'
# require 'bigdecimal/util'
require 'aws-sdk-ssm'
require 'aws-sdk-dynamodb'
require 'pusher'

AWS_REGION     = 'eu-west-1'

# bundle update
# sam build --use-container
# sam deploy --guided

# to test: from the lambdas directory: ./run.rb ingest conping.json

# or

# from the lambda directory:
# irb
# $debug = true
# require_relative "ingest/app.rb"
# reprocess(201683)

# require 'logger'
# DB.loggers << Logger.new($stdout)

# TEST_MESSAGE = {
#     "source": "ping_us_east_1",
#     "payload": {
#         "target": "3.80.0.0",
#         "pings": 10,
#         "packet_loss_percentage": "0",
#         "rtt": {
#             "min": "214.355",
#             "avg": "214.621",
#             "max": "215.655",
#             "mdev": "0.458"
#         }
#     },
#     "received": 1607245090.907,
#     "uid": "1607245090.907.66754463"
# }
# message = TEST_MESSAGE

env = {}

if $debug.nil?
  ssm = Aws::SSM::Client.new(region: AWS_REGION)
  env = ssm.get_parameters({ names: %w(PUSHER_APP_ID PUSHER_KEY PUSHER_SECRET PUSHER_CHANNEL) })[:parameters].map { |e| [e[:name], e[:value]] }.to_h
end

DDB = Aws::DynamoDB::Client.new(region: 'eu-west-1')

PUSHER_CHANNEL = env['PUSHER_CHANNEL']
PUSHER = ($debug ? nil : Pusher::Client.new(
    app_id:    env['PUSHER_APP_ID'],
    key:       env['PUSHER_KEY'],
    secret:    env['PUSHER_SECRET'],
    cluster:   'eu',
    encrypted: true,
  )
)

def lambda_handler(event:, context:)
  event['Records'].each do |record|
    payload    = record['Sns']
    message_id = payload['MessageId']
    message    = JSON.parse(payload['Message'])
    puts "MessageId: #{message_id}"         # neccessary to be able to find this in cloudwatche's logs
    process(message)
  end
  true
end

def process(message)
  puts message
  pusher(message)
  store_in_ddb_sources(message)
  store_in_ddb_events(message)
end

def pusher(message)
  PUSHER.trigger(PUSHER_CHANNEL, 'event', { message: message })  if PUSHER
end

def store_in_ddb_events(message)
  ttl = 4742280267;  # 100 years from 11 April 2020
  ttl = Time.new.to_i +   60*60  if message['source'].end_with?('_alive')
  ttl = Time.new.to_i +   60*60  if message['source'].start_with?('weather_')
  ttl = Time.new.to_i + 2*60*60  if message['source']=='iot-relay'
  put_item('events', {
    source:     message['source'],
    uid:        message['uid'],
    payload:    message['payload'],
    received:   message['received'],
    receivedAt: Time.at(message['received']).strftime('%Y-%m-%dT%H:%M:%S.%L%Z'),
    ttl:        ttl,
  })
end

def store_in_ddb_sources(message)
  put_item('sources', {
    source:     message['source'],
    uid:        message['uid'],
    payload:    message['payload'],
    received:   message['received'],
    receivedAt: Time.at(message['received']).strftime('%Y-%m-%dT%H:%M:%S.%L%Z'),
  })
end

def put_item(table_name, message)
  params = {
    table_name: table_name,
    item:       message
  }
  begin
    DDB.put_item(params)
  rescue  Aws::DynamoDB::Errors::ServiceError => error
    puts 'Unable to add event'
    puts error.message
  end
end

