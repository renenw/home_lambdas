require 'json'
require 'securerandom'
require 'aws-sdk-ssm'
require 'aws-sdk-ses'
require 'aws-sdk-dynamodb'
require 'net/http'
require 'uri'
# require 'bigdecimal/util'

AWS_REGION            = 'eu-west-1'
SKIP_AUTH             = ['/ping', '/otp', '/auth']
VALID_EMAIL_ADDRESSES = %w(renen@121.co.za rosalind.watermeyer@gmail.com sofie.watermeyer@gmail.com finn.watermeyer@gmail.com)

# NB NB: start with this article, do not google!
# to build this for deployment, use these instructions: https://blog.shikisoft.com/ruby-aws-lambda-sam-cli-rds-mysql/

# docker run -v "$PWD":/var/task -it lambci/lambda:build-ruby2.7 /bin/bash
# bundle update
# sam build --use-container
# sam deploy --guided

# to test: from the lambdas directory: ./run.rb rsg event.json

DDB = Aws::DynamoDB::Client.new(region: 'eu-west-1')


def lambda_handler(event:, context:)
  path          = event['path']
  body          = event['body']
  json          = ( body ? JSON.parse(body) : nil )
  qs            = event['queryStringParameters']
  authenticated = SKIP_AUTH.include?(path)
  authenticated = validate_key(qs)  if !authenticated
  response      =  route_request(path: path, qs: qs, payload: json) if authenticated
  if $debug.nil?
    {
      statusCode: (authenticated ? 200 : 403),
      headers: { "Access-Control-Allow-Origin" => "*" },
      body: response.to_json
    }
  else
    pp response
  end
end

def route_request(path:, qs:, payload:)
  case path
  when '/ping'           then 'pong'
  when '/otp'            then otp(qs)
  when '/auth'           then auth(qs)
  when '/action'         then action(payload['action'], payload['payload'])
  end  
end

def validate_key(qs)
  email   = qs['e']
  key     = qs['k']
  ddb     = get_item(:users, email: email)
  (ddb['apiKey']==key)
end

def action(action, instruction)
  switch_on(instruction['switchId'], instruction['duration_s'])  if (action=='switchIrrigationOn')
end


def switch_on(switch_id, duration_seconds)
  ssm                      = Aws::SSM::Client.new(region: AWS_REGION)
  auth_key                 = ssm.get_parameters({ names: %w(HOME_NGINX_API_KEY) })[:parameters].map { |e| [e[:name], e[:value]] }.to_h['HOME_NGINX_API_KEY']
  url                      = URI("http://home.121.co.za:9077/on?switch=#{switch_id}&duration=#{duration_seconds}")
  http                     = Net::HTTP.new(url.host, url.port);
  # http.use_ssl             = true
  request                  = Net::HTTP::Get.new(url)
  request["Authorization"] = auth_key
  response                 = http.request(request)
  true
end



def auth(qs)
  key     = nil
  channel = nil
  email   = qs['email']
  otp     = qs['otp']
  ddb     = get_item(:users, email: email)
  if ddb && ddb['otp']==otp
    ssm     = Aws::SSM::Client.new(region: AWS_REGION)
    channel = ssm.get_parameters({ names: %w(PUSHER_CHANNEL) })[:parameters].map { |e| [e[:name], e[:value]] }.to_h['PUSHER_CHANNEL']
    key     = SecureRandom.uuid
    put_item(:users, {
      email:  email,
      apiKey: key,
      otp:    SecureRandom.alphanumeric(6),
    })
  end
  {
    apiKey:   key,
    channel: channel,
  }
end

def otp(qs)
  recipient = qs['email']
  if VALID_EMAIL_ADDRESSES.include?(recipient)
    otp     = get_otp(recipient)
    send_otp(recipient, otp)
  end
  true
end

def send_otp(recipient, otp)
  ses       = Aws::SES::Client.new(region: AWS_REGION)
  resp      = ses.send_email({
    destination: { to_addresses: [recipient] },
    message: {
      body: {
        html: {
          charset: 'UTF-8',
          data:    "<p>Your PIN is #{otp}</p>",
        },
        text: {
          charset: 'UTF-8',
          data:    "Your PIN is #{otp}.",
        },
      },
      subject: {
        charset: 'UTF-8',
        data:    "OTP: #{otp}",
      },
    },
    source: 'hello@121.co.za',
  })
end

def get_otp(email)
  pin = 6.times.map { (rand*10).to_i.to_s }.join
  put_item(:users, {
    email:     email,
    otp:       pin,
  })
  pin
end


def get_item(table_name, keys)
  params = {
    table_name: table_name,
    item:       keys
  }
  DDB.get_item({
    table_name: table_name,
    key:        keys,
  })['item']
end

def put_item(table_name, message)
  params = {
    table_name: table_name,
    item:       message,
  }
  DDB.put_item(params)
end
