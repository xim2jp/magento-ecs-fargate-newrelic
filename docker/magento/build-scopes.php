<?php
/**
 * Build-time helper. `setup:static-content:deploy` resolves the default website/store
 * to build URLs, which normally needs the database. During the image build there is
 * no database, so we temporarily write the default store scopes into app/etc/config.php
 * (the same structure `bin/magento app:config:dump` produces) and remove them again
 * afterwards so the runtime reads scopes from the database.
 *
 *   php build-scopes.php app/etc/config.php add
 *   php build-scopes.php app/etc/config.php remove
 */
[, $file, $mode] = $argv + [null, 'app/etc/config.php', 'add'];

$config = include $file;

if ($mode === 'remove') {
    unset($config['scopes']);
} else {
    $config['scopes'] = [
        'websites' => [
            'admin' => ['website_id' => '0', 'code' => 'admin', 'name' => 'Admin', 'sort_order' => '0', 'default_group_id' => '0', 'is_default' => '0'],
            'base'  => ['website_id' => '1', 'code' => 'base', 'name' => 'Main Website', 'sort_order' => '0', 'default_group_id' => '1', 'is_default' => '1'],
        ],
        'groups' => [
            0 => ['group_id' => '0', 'website_id' => '0', 'name' => 'Default', 'root_category_id' => '0', 'default_store_id' => '0', 'code' => 'default'],
            1 => ['group_id' => '1', 'website_id' => '1', 'name' => 'Main Website Store', 'root_category_id' => '2', 'default_store_id' => '1', 'code' => 'main_website_store'],
        ],
        'stores' => [
            'admin'   => ['store_id' => '0', 'code' => 'admin', 'website_id' => '0', 'group_id' => '0', 'name' => 'Admin', 'sort_order' => '0', 'is_active' => '1'],
            'default' => ['store_id' => '1', 'code' => 'default', 'website_id' => '1', 'group_id' => '1', 'name' => 'Default Store View', 'sort_order' => '0', 'is_active' => '1'],
        ],
    ];
}

file_put_contents($file, "<?php\nreturn " . var_export($config, true) . ";\n");
echo "config.php scopes: {$mode}\n";
