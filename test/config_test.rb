require_relative "test_helper"

class ConfigTest < Minitest::Test
  def test_configs
    config = JEB::Config.new(app_hash: {
      "production" => {
        "default" => {
          "aws:elasticbeanstalk:command:" => {
            "BatchSize" => 30
          }
        },
        "web" => {
          "type" => "web",
          "option_settings" => {
            "some" => "option"
          }
        }
      }
    }, eb_configs: {
      Pathname("foo.config") => "Hello: World",
      Pathname("bar.config") => "option_settings: <%= 1+2 %>"
    })

    assert_equal [:web], config.each_worker(env: :production).to_a
    assert_equal({ "some" => "option" }, config.option_settings(env: :production, worker: :web))

    assert_equal({
                   Pathname("foo.config") => "Hello: World",
                   Pathname("bar.config") => "option_settings: 3"
                 }, Hash[config.each_config.to_a])
  end
end
