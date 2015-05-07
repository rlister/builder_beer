#!/usr/bin/env ruby

## send Resque queue data to cloudwatch;
## depends on env vars:
##   REDIS_URL
##   CLOUDWATCH_NAMESPACE [optional]
## and preferably setup IAM role on instances, or use:
##   AWS_ACCESS_KEY_ID
##   AWS_DEFAULT_REGION
##   AWS_SECRET_ACCESS_KEY

require 'aws-sdk'
require 'resque'

## get size of each queue
metric_data = Resque.queues.map do |queue|
  {
    dimensions: [{ name: 'QueueName', value: queue }],
    metric_name: 'Size',
    value: Resque.size(queue),
    unit: 'Count'
  }
end

## add count of workers currently working
metric_data <<
  {
    dimensions: [{ name: 'Workers', value: 'Working' }],
    metric_name: 'Size',
    value: Resque.working.size,
    unit: 'Count'
  }

## send to cloudwatch
Aws::CloudWatch::Client.new.put_metric_data(
  namespace: ENV.fetch('CLOUDWATCH_NAMESPACE', 'Builder'),
  metric_data: metric_data
)

## output for the log
metric_data.each do |datum|
  puts datum
end
