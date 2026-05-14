extends SceneTree

const ARG_PREFIX = "--zip-to-unpack "

func _init():
	var zip_path: String
	for arg in OS.get_cmdline_args():
		if arg.begins_with(ARG_PREFIX):
			zip_path = arg.right(arg.length() - ARG_PREFIX.length())
			break

	if !zip_path:
		print("No file specified")
		return

	print("Unpacking %s..." % zip_path)

	var zip := ZIPReader.new()
	var err := zip.open(zip_path)
	if err != OK:
		print("Failed to open zip: %s" % zip_path)
		return

	var files := zip.get_files()
	if files.is_empty():
		print("Zip is empty")
		zip.close()
		return

	# Output directory: same location as zip, subfolder named after zip filename
	var base_name := zip_path.get_file().get_basename()
	var out_dir := zip_path.get_base_dir() + "/" + base_name + "/"
	DirAccess.make_dir_recursive_absolute(out_dir)

	# Detect if all entries share a common top-level directory
	var prefix := ""
	for entry in files:
		var slash_pos := entry.find("/")
		if slash_pos < 0:
			prefix = ""
			break
		var candidate := entry.left(slash_pos + 1)
		if prefix.is_empty():
			prefix = candidate
		elif prefix != candidate:
			prefix = ""
			break

	for path in files:
		# Strip common top-level directory
		var extract_path := path
		if not prefix.is_empty() and path.begins_with(prefix):
			extract_path = path.substr(prefix.length())

		if extract_path.is_empty() or extract_path.ends_with("/"):
			if not extract_path.is_empty():
				DirAccess.make_dir_recursive_absolute(out_dir + extract_path)
			continue

		var data := zip.read_file(path)
		var full_path := out_dir + extract_path

		DirAccess.make_dir_recursive_absolute(full_path.get_base_dir())

		var out_file := FileAccess.open(full_path, FileAccess.WRITE)
		if out_file:
			out_file.store_buffer(data)
			out_file.close()
			print("Extracted: %s" % extract_path)
		else:
			push_warning("Failed to write: %s" % full_path)

	zip.close()

	# Delete the zip file after extraction
	DirAccess.remove_absolute(zip_path)
	print("Done! Removed %s" % zip_path)
