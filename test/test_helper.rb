$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'jack_and_the_elastic_beanstalk'

require 'minitest/autorun'

JEB = JackAndTheElasticBeanstalk

module TestHelper
  def tmpdir
    Dir.mktmpdir do |dir|
      yield Pathname(dir)
    end
  end
end

class Minitest::Test
  include TestHelper
end
