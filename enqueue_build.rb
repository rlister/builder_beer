#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'
require 'resque'

require './builder'

Resque.enqueue(Builder, *ARGV)
