#
# * grunt-smart-assets
# *
# *
# * Copyright (c) 2014 Shapovalov Alexandr
# * Licensed under the MIT license.
#
"use strict"

module.exports = (grunt) ->

	path 	= require('path')
	crypto 	= require('crypto');
	_ 		= require('lodash');

	run_task = (task, config) ->
		default_config = grunt.config.get('task') || {};
		default_config['smart_assets'] = config
		grunt.config.set(task, default_config);
		grunt.task.run("#{task}:smart_assets");

	md5 = (filepath) ->
		hash = crypto.createHash('md5');
		grunt.log.verbose.write("Hashing #{filepath} ...");
		hash.update(grunt.file.read(filepath), 'utf8');
		return hash.digest('hex').slice(0, 8);


	patterns = [
		[/<script.+src=['"]([^"']+)["']/gim]
		[/<link[^\>]+href=['"]([^"']+)["']/gim]
		[/<img[^\>]*[^\>\S]+src=['"]([^"']+)["']/gim]
		[/<image[^\>]*[^\>\S]+xlink:href=['"]([^"']+)["']/gim]
		[/<image[^\>]*[^\>\S]+src=['"]([^"']+)["']/gim]
		[/<(?:img|source)[^\>]*[^\>\S]+srcset=['"]([^"'\s]+)(?:\s\d[mx])["']/gim]
		[/<source[^\>]+src=['"]([^"']+)["']/gim]
		#[/<a[^\>]+href=['"]([^"']+)["']/gim]
		[/<input[^\>]+src=['"]([^"']+)["']/gim]
		[/data-(?!main).[^=]+=['"]([^'"]+)['"]/gim]
		[
			[/data-main\s*=['"]([^"']+)['"]/gim]
			(m) ->
				if m.match(/\.js$/)
					return m
				else
					return m + '.js'

			(m) ->
				return m.replace('.js', '')
		]
		[/<object[^\>]+data=['"]([^"']+)["']/gim]
	]

	#standart task need
	grunt.task.loadNpmTasks('grunt-contrib-copy')

	# Please see the Grunt documentation for more information regarding task
	# creation: http://gruntjs.com/creating-tasks
	grunt.registerMultiTask "smart_assets", ->

		tasks_to_run = []

		# Merge task-specific and/or target-specific options with these defaults.
		options = @options()
		defaults_options =
			files:
				src: '**/*'
				streamTasks : {}
			html:
				src: '**/*'


		options = _.merge(defaults_options, options)

		if !options.files.cwd? or !options.files.dest?
			grunt.fail.fatal "Your not configure files.cwd or files.dest!"


		#clean dist before other tasks run
		if options.files.cleanDest
			grunt.task.loadNpmTasks('grunt-contrib-clean')
			run_task 'clean', options.files.dest

		grunt.registerTask "smart_assets_files", ->
			files = {}
			grunt.file.expand({cwd: options.files.cwd, filter: 'isFile'}, options.files.src).forEach (file)->

				ext = path.extname file;
				find = -1;
				if options.files.streamTasks?
					_.forEach options.files.streamTasks, (values,key)->
						find = key unless _.indexOf(values.from, ext) is -1

				unless find is -1
					files[find] = new Array() unless _.isArray files[find]
					files[find].push file
				else
					files['copy'] = new Array() unless _.isArray files['copy']
					files['copy'].push file

			_.forEach files, (val, task) ->
				src = {}
				task_options = {}

				if options.files.streamTasks[task]?['options']? and _.isObject options.files.streamTasks[task]['options']
					task_options.options = options.files.streamTasks[task]['options']

				_.forEach val, (file) ->
					ext = path.extname(file)
					result_ext = (if options.files.streamTasks[task]?.to? then options.files.streamTasks[task].to else '')
					if result_ext != ''
						result_path = path.join(options.files.dest , file).replace(ext, result_ext)
					else
						result_path = path.join(options.files.dest , file)
					src[result_path] = path.join( options.files.cwd , file)

				task_options['files'] = src
				run_task task, task_options

		tasks_to_run.push "smart_assets_files"

		if _.isObject options.files.afterTasks
			grunt.registerTask "smart_assets_filesAfter", ->

				defaults =
					expand: true
					cwd : options.files.dest
					dest: options.files.dest

				_.forEach options.files.afterTasks, (options, task)->
					run_task task, _.merge(defaults, options)

			tasks_to_run.push "smart_assets_filesAfter"

		if _.isObject options.html
			if !options.html.cwd? or !options.html.dest?
				grunt.fail.fatal "Your not configure html.cwd or html.dest!"

			grunt.registerTask "smart_assets_html", ->

				msg_ok 		= [] unless _.isArray(msg_ok)
				msg_warn 	= [] unless _.isArray(msg_warn)

				grunt.file.expand({cwd: options.html.cwd, filter: 'isFile'}, options.html.src).forEach (file_name)->
					content = grunt.file.read path.join(options.html.cwd, file_name)

					patterns.forEach (pattern) ->

						patrn = if pattern[0]?[0]? then  pattern[0][0] else pattern[0]
						match =  content.match patrn

						if match != null
							match.forEach (result) ->
								result.match pattern[0]

								file = RegExp.$1
								file_ext = path.extname(file) #берем расширение файла
								#ищем результирующее
								result_ext = if options.files.streamTasks[file_ext.split('.').pop()]?.to? then options.files.streamTasks[file_ext.split('.').pop()].to else ''
								if result_ext != ''
									result_file =file.replace file_ext, result_ext
								else
									result_file =file

								if pattern[1]? then result_file = pattern[1](result_file)
								result_file_path = path.join(options.html.assetDir, result_file).replace(options.files.cwd, options.files.dest)
								result_file = path.join(options.html.assetDir, result_file).replace(options.files.cwd, options.files.dest).replace(options.html.assetDir, '')

								if grunt.file.exists(result_file_path) && grunt.file.isFile(result_file_path)
									if pattern[2]? then result_file = pattern[2](result_file)
									if options.html?.rev? and options.html.rev and !pattern[2]? then result_file = [result_file, md5(result_file_path)].join('?')
									content = content.replace file, result_file
									msg_ok.push("Replace #{file} to #{result_file}")
								else
									msg_warn.push("Not replaced in html (ignore it if all ok) - #{file}")

					if msg_ok.length
						grunt.log.subhead("Changed path in html #{path.join(options.html.cwd, file_name)}:")
						msg_ok.forEach (msg) ->
							grunt.log.ok(msg)

					if msg_warn.length
						grunt.log.subhead('Error? No! Just warning...:')
						msg_warn.forEach (msg) ->
							grunt.log.warn(msg)

					grunt.file.write path.join(options.html.dest, file_name), content

			tasks_to_run.push "smart_assets_html"

		grunt.task.run(tasks_to_run);
