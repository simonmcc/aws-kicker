# Kicker

TODO: Write a gem description

## Installation

Add this line to your application's Gemfile:

    gem 'kicker'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install kicker

## Usage

TODO: Write usage instructions here

## Stackfile
The Stackfile is a ruby based config that is eval'd at runtime.  Here's a sample config:
	
	module StackConfig
	  Stacks = {
	    # eu-west-1-simon-micro
	    'rentpro-bmtw' => {
	      :provider               => 'AWS',
	      :aws_access_key_id      => ENV['AWS_ACCESS_KEY'],
	      :aws_secret_access_key  => ENV['AWS_SECRET_KEY'],
	      :keypair                => 'jobdoneright',
	      # generic
	      :region                 => 'eu-west-1',
	      :availability_zone      => 'eu-west-1a',
	      :flavor_id              => 't1.micro',
	      :image_id               => 'ami-ffecde8b',
	      :dns_domain             => 'bmtw.net',
	      :dns_id                 => 'Z2NT1FUYUEREUK',
	      :roles                  => {
	        'rentpro-db'  => { 
	          :count => 1, 
	          :publish_private_ip => true, 
	          :flavor_id => 'm1.small' 
	        },
	        'rentpro-web' => { 
	          :count => 1, 
	          :dns_wildcard => true 
	        }
	      }
	    }
	  }
	end

2 instances will be booted, rentpro-db & rentpro-web

### Global Parameters
| Name | Type | Description |
|------|------|------------ |
| mime_encode_user_data | Boolean | Defaults to True. When set to False sends only the bootstrap script as user-data, useful for working around issues with Ubuntu Hardy's iffy EC2 Init handling |

#### Role Parameters

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
