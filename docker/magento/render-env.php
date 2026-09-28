<?php
/**
 * Renders app/etc/env.php from environment variables so that every container
 * (web, cron, install) shares the same configuration without baking secrets
 * into the image. Values under "system" override the database configuration.
 */
$env = static function (string $key, string $default = ''): string {
    $value = getenv($key);
    return ($value === false || $value === '') ? $default : $value;
};

$baseUrl        = $env('MAGENTO_BASE_URL', 'http://localhost/');
$redisHost      = $env('MAGENTO_REDIS_HOST', '127.0.0.1');
$redisPort      = $env('MAGENTO_REDIS_PORT', '6379');
$openSearchHost = $env('MAGENTO_OPENSEARCH_HOST', 'http://localhost');
$openSearchPort = $env('MAGENTO_OPENSEARCH_PORT', '9200');
$baseHost       = (string) parse_url($baseUrl, PHP_URL_HOST);
$isHttps        = parse_url($baseUrl, PHP_URL_SCHEME) === 'https';

$redisCache = static fn (string $db): array => [
    'backend' => 'Magento\\Framework\\Cache\\Backend\\Redis',
    'backend_options' => [
        'server'          => $redisHost,
        'port'            => $redisPort,
        'database'        => $db,
        'password'        => '',
        'compress_data'   => '1',
        'compression_lib' => '',
    ],
];

$config = [
    'backend' => ['frontName' => $env('MAGENTO_ADMIN_FRONTNAME', 'admin')],
    'crypt'   => ['key' => $env('MAGENTO_CRYPT_KEY')],
    'db' => [
        'table_prefix' => '',
        'connection' => [
            'default' => [
                'host'           => $env('MAGENTO_DB_HOST'),
                'dbname'         => $env('MAGENTO_DB_NAME', 'magento'),
                'username'       => $env('MAGENTO_DB_USER', 'magento'),
                'password'       => $env('MAGENTO_DB_PASSWORD'),
                'model'          => 'mysql4',
                'engine'         => 'innodb',
                'initStatements' => 'SET NAMES utf8;',
                'active'         => '1',
                'driver_options' => [1014 => false],
            ],
        ],
    ],
    'resource'        => ['default_setup' => ['connection' => 'default']],
    'x-frame-options' => 'SAMEORIGIN',
    'MAGE_MODE'       => $env('MAGE_MODE', 'production'),
    'session' => [
        'save' => 'redis',
        'redis' => [
            'host'                  => $redisHost,
            'port'                  => $redisPort,
            'password'              => '',
            'timeout'               => '2.5',
            'persistent_identifier' => '',
            'database'              => '2',
            'compression_threshold' => '2048',
            'compression_library'   => 'gzip',
            'log_level'             => '3',
            'max_concurrency'       => '6',
            'break_after_frontend'  => '5',
            'break_after_adminhtml' => '30',
            'first_lifetime'        => '600',
            'bot_first_lifetime'    => '60',
            'bot_lifetime'          => '7200',
            'disable_locking'       => '0',
            'min_lifetime'          => '60',
            'max_lifetime'          => '2592000',
        ],
    ],
    'cache' => [
        'frontend' => [
            'default'    => ['id_prefix' => 'mg_'] + $redisCache('0'),
            'page_cache' => ['id_prefix' => 'mg_'] + $redisCache('1'),
        ],
    ],
    'lock' => ['provider' => 'db'],
    'cache_types' => [
        'config'                 => 1,
        'layout'                 => 1,
        'block_html'             => 1,
        'collections'            => 1,
        'reflection'             => 1,
        'db_ddl'                 => 1,
        'compiled_config'        => 1,
        'eav'                    => 1,
        'customer_notification'  => 1,
        'config_integration'     => 1,
        'config_integration_api' => 1,
        'full_page'              => 1,
        'config_webservice'      => 1,
        'translate'              => 1,
    ],
    'install' => ['date' => 'Mon, 01 Jun 2026 00:00:00 +0000'],
    // Varnish runs in the same task (localhost); cache purges are sent here.
    'http_cache_hosts' => [['host' => '127.0.0.1', 'port' => '80']],
    'queue' => ['consumers_wait_for_messages' => 0],
    'cron_consumers_runner' => [
        'cron_run'     => true,
        'max_messages' => 1000,
        'consumers'    => [],
    ],
    'downloadable_domains' => [$baseHost],
    'system' => [
        'default' => [
            'web' => [
                'unsecure' => ['base_url' => $baseUrl],
                'secure'   => [
                    'base_url'         => $baseUrl,
                    // TLS terminates at the ALB; Varnish/nginx forward X-Forwarded-Proto
                    'offloader_header' => 'X-Forwarded-Proto',
                    'use_in_frontend'  => $isHttps ? '1' : '0',
                    'use_in_adminhtml' => $isHttps ? '1' : '0',
                ],
            ],
            'catalog' => [
                'search' => [
                    'engine'                     => 'opensearch',
                    'opensearch_server_hostname' => $openSearchHost,
                    'opensearch_server_port'     => $openSearchPort,
                    'opensearch_index_prefix'    => 'magento2',
                    'opensearch_enable_auth'     => '0',
                    'opensearch_server_timeout'  => '15',
                ],
            ],
            'system' => [
                'full_page_cache' => [
                    'caching_application' => '2',
                    'ttl'                 => '86400',
                    'varnish' => [
                        'backend_host' => '127.0.0.1',
                        'backend_port' => '8080',
                        'access_list'  => '127.0.0.1',
                        'grace_period' => '300',
                    ],
                ],
            ],
        ],
    ],
];

echo "<?php\nreturn " . var_export($config, true) . ";\n";
