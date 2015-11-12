def readme():
    with open('README.md') as f:
        return f.read()

from setuptools import setup

setup(
    name             = 'smc_pyutil',
    version          = '1.0',
    description      = 'SageMathCloud Python Utilities',
    long_description = readme(),
    url              = 'https://github.com/sagemathinc/smc',
    author           = 'SageMath, Inc.',
    author_email     = 'office@sagemath.com',
    license          = 'GPLv3+',
    packages         = ['smc_pyutil'],
    install_requires = ['markdown2'],
    zip_safe        = False,
    classifiers     = [
        'License :: OSI Approved :: GPLv3',
        'Programming Language :: Python :: 2.7',
        'Topic :: Mathematics :: Server',
    ],
    keywords        = 'server mathematics cloud',
    scripts         = ['smc_pyutil/bin/smc-sage-server'],
    entry_points    = {
        'console_scripts': [
            'open                 = smc_pyutil.smc_open:main',
            'smc-sagews2pdf       = smc_pyutil.sagews2pdf:main',
            'smc-sws2sagews       = smc_pyutil.sws2sagews:main',
            'smc-docx2txt         = smc_pyutil.docx2txt:main',
            'smc-open             = smc_pyutil.smc_open:main',
            'smc-new-file         = smc_pyutil.new_file:main',
            'smc-status           = smc_pyutil.status:main',
            'smc-jupyter          = smc_pyutil.jupyter_notebook:main',
            'smc-ls               = smc_pyutil.git_ls:main',
            'smc-compute          = smc_pyutil.smc_compute:main',
            'smc-start            = smc_pyutil.start_smc:main',
            'smc-stop             = smc_pyutil.stop_smc:main'
        ]
    },
    include_package_data = True
)
