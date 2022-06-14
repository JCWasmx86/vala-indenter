vala_indenter_sources = [
  'main.vala',
]

vala_indenter_deps = [
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('gtksourceview-5'),
  dependency('gtk4'),
  dependency('libadwaita-1')
]

executable('vala-indenter', vala_indenter_sources,
  vala_args: '--target-glib=2.58',  dependencies: vala_indenter_deps,
  install: true,
)
