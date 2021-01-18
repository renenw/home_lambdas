require 'json'
require 'aws-sdk-ssm'
require 'aws-sdk-ses'
# require 'net/http'
# require 'uri'
# require 'bigdecimal/util'

AWS_REGION     = 'eu-west-1'

# NB NB: start with this article, do not google!
# to build this for deployment, use these instructions: https://blog.shikisoft.com/ruby-aws-lambda-sam-cli-rds-mysql/

# docker run -v "$PWD":/var/task -it lambci/lambda:build-ruby2.7 /bin/bash
# bundle update
# sam build --use-container
# sam deploy --guided

# to test: from the lambdas directory: ./run.rb rsg assess.json


def lambda_handler(event:, context:)
  puts event.to_json
  path = event['path']
  body = event['body']
  json = ( body ? JSON.parse(body) : nil )
  qs   = event['queryStringParameters']
  puts path
  response = case path
  when '/ping'           then 'pong'
  when '/sendOtp'        then otp(qs)
  when '/auth'           then auth(qs)
  end
  puts response
  if $debug.nil?
    {
      statusCode: 200,
      headers: { "Access-Control-Allow-Origin" => "*" },
      body: response.to_json
    }
  else
    pp response
  end
end

def auth(qs)
  r     = nil
  email = qs['email']
  otp   = qs['otp']
  key   = SecureRandom.uuid
  # n     = DB[:Users].where(email: email).where(otp: otp).update(otp: nil, apiKey: key)
  # if (n==1)
  #   r = DB[:Users].where(email: email).where(apiKey: key).join(:Customers, id: :customerId).select(:apiKey, :slackUrl, :postUrl, :name).all.first
  # end
  r
end

def otp(qs)
  recipient = qs['email']
  otp       = get_otp(recipient)
  send_otp(recipient, otp)
  nil
end

def send_otp(recipient, otp)
  ses       = Aws::SES::Client.new(region: AWS_REGION)
  resp      = ses.send_email({
    destination: { to_addresses: [recipient] },
    message: {
      body: {
        html: {
          charset: 'UTF-8',
          data:    "<p>Your RSG PIN is #{otp}</p>",
        },
        text: {
          charset: 'UTF-8',
          data:    "Your RSG PIN is #{otp}.",
        },
      },
      subject: {
        charset: 'UTF-8',
        data:    "RSG OTP: #{otp}",
      },
    },
    source: 'info@acusense.io',
  })
end

def get_otp(email)
  pin = 6.times.map { (rand*10).to_i.to_s }.join
  n   = DB[:Users].where(email: email).update(otp: pin)
  if (n==0)
    customer_id = DB[:Customers].insert(name: 'ACME Inc.')
    DB[:Users].insert(customerId: customer_id, email: email, otp: pin)
  end
  pin
end

