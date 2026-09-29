{
    'name': 'Disable Publisher Warranty & Set Expiration',
    'version': '19.0.1.0',
    'category': 'Technical',
    'summary': 'Block ping to odoo server, turn off cronjob and database expired message',
    'depends': ['mail'],
    'data': [
        'data/ir_cron_data.xml',
        'data/ir_config_parameter_data.xml',
    ],
    'installable': True,
    'auto_install': True,
    'license': 'MIT',
}