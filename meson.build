project('vala-indenter', ['c', 'vala'],
          version: '0.1.0',
    meson_version: '>= 0.59.0',
  default_options: [ 'warning_level=2',
                     'werror=false',
                   ],
)
vapi_dir = meson.current_source_dir() / 'src'
add_project_arguments(['--vapidir', vapi_dir], language: 'vala')
add_project_arguments(['-fanalyzer'], language: 'c')
subdir('src')