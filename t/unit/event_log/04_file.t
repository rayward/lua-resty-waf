use Test::Nginx::Socket::Lua;
use Path::Tiny qw(path);
use Cwd qw(cwd);

my $pwd = cwd();

our $HttpConfig = qq{
	lua_package_path "$pwd/lib/?.lua;;";
	lua_package_cpath "$pwd/lib/?.lua;;";
};

add_block_preprocessor(sub {
	path("/tmp/waf.log")->remove;
	path("/tmp/waf.log")->touch;

	if ( path("/tmp/waf.log")->exists ) {
		print "waf.log exists";
	} else {
		print "waf.log doesn't exist";
	}
});

repeat_each(3);
plan tests => repeat_each() * 2 * blocks() + 3;

no_shuffle();
run_tests();

__DATA__

=== TEST 1: Write an entry to file without error
--- http_config eval: $::HttpConfig
--- config
	location /t {
		access_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local log           = require "resty.waf.log"
			local waf           = lua_resty_waf:new()

			waf:set_option("event_log_target", "file")
			waf:set_option("event_log_target_path", "/tmp/waf.log")

			log.write_log_events[waf._event_log_target](waf, {foo = "bar"})
		}

		content_by_lua_block {ngx.exit(ngx.HTTP_OK)}
	}
--- request
GET /t
--- error_code: 200
--- error_log
--- no_error_log
[error]
--- log read_file: /tmp/waf.log
--- content
{"foo": "bar"}

=== TEST 2: Fatally fail when path is unset
--- http_config eval: $::HttpConfig
--- config
	location /t {
		access_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local log           = require "resty.waf.log"
			local waf           = lua_resty_waf:new()

			waf:set_option("event_log_target", "file")

			log.write_log_events[waf._event_log_target](waf, {foo = "bar"})
		}

		content_by_lua_block {ngx.exit(ngx.HTTP_OK)}
	}
--- request
GET /t
--- error_code: 500
--- error_log
Event log target path is undefined in file logger

=== TEST 3: Warn when file path cannot be opened
--- http_config eval: $::HttpConfig
--- config
	location /t {
		access_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local log           = require "resty.waf.log"
			local waf           = lua_resty_waf:new()

			waf:set_option("event_log_target", "file")
			waf:set_option("event_log_target_path", "/tmp/waf.log")

			io.open = function() return false end

			log.write_log_events[waf._event_log_target](waf, {foo = "bar"})
		}

		content_by_lua_block {ngx.exit(ngx.HTTP_OK)}
	}
--- request
GET /t
--- error_code: 200
--- error_log
Could not open /tmp/waf.log
--- no_error_log
[error]


=== TEST 4: App name prepended to message
--- http_config eval: $::HttpConfig
--- config
	location /t {
		access_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local log           = require "resty.waf.log"
			local waf           = lua_resty_waf:new()

			waf:set_option("event_log_target", "file")
			waf:set_option("event_log_target_path", "/tmp/waf.log")
			waf:set_option("event_log_app_name", "file_log")

			log.write_log_events[waf._event_log_target](waf, {foo = "bar"})
		}

		content_by_lua_block {ngx.exit(ngx.HTTP_OK)}
	}
--- request
GET /t
--- error_code: 200
--- error_log
--- no_error_log
[error]
--- log read_file: /tmp/waf.log
--- content
file_log: {"foo": "bar"}
