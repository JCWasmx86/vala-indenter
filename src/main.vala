/* main.vala
 *
 * Copyright 2022 JCWasmx86
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

int main (string[] args) {
	GLib.Environment.set_variable ("G_MESSAGES_DEBUG", "all", true);
	var app = new Adw.Application ("io.example.foo", GLib.ApplicationFlags.FLAGS_NONE);
	app.activate.connect (() => {
		var w = new Gtk.ApplicationWindow (app);
		var gsv = new GtkSource.View ();
		var sc = new Gtk.ScrolledWindow ();
		sc.child = gsv;
		w.child = sc;
		gsv.indenter = new ValaIndenter ();
		gsv.set_auto_indent (true);
		gsv.space_drawer.enable_matrix = true;
		((GtkSource.Buffer) gsv.buffer).set_language (GtkSource.LanguageManager.get_default ().get_language ("vala"));
		gsv.set_show_line_numbers (true);
		var c = new Gtk.CssProvider ();
		c.load_from_data ("textview { font-family: Monospace; font-size: 12pt; }".data);
		gsv.get_style_context ().add_provider (c, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
		w.present ();
	});
	app.run ();
	return 0;
}

class ValaIndenter : GLib.Object, GtkSource.Indenter {
	string extract_indent (string str) {
		var sb = new StringBuilder ();
		for (var i = 0; i < str.length; i++) {
			if (str[i].isspace () && str[i] != '\n') {
				sb.append_c (str[i]);
			} else {
				break;
			}
		}
		return sb.str;
	}

	public void indent (GtkSource.View view, ref Gtk.TextIter iter) {
		var line_no = iter.get_line ();
		Gtk.TextIter previous_line_iter;
		view.buffer.get_iter_at_line (out previous_line_iter, line_no - 1);
		var previous_line_str = previous_line_iter.get_text (iter);
		var previous_line_stripped = previous_line_str.strip ();
		// Insert new // comment
		if (previous_line_stripped.has_prefix ("//")) {
			info ("Continuing // comment");
			view.buffer.insert (ref iter, extract_indent (previous_line_str) + previous_line_stripped.split ("//")[0]
			                    + "// ", -1);
			return;
		}
		// Now try to continue a multiline comment
		if (previous_line_stripped.has_prefix ("*") && !previous_line_stripped.has_prefix ("*/")) {
			info ("Continuing multi-line comment");
			var found_start = false;
			var curr_line = line_no - 2;
			Gtk.TextIter tmp_iter;
			Gtk.TextIter tmp2_iter = previous_line_iter;
			do {
				view.buffer.get_iter_at_line (out tmp_iter, curr_line);
				if (tmp_iter.get_text (tmp2_iter).strip ().has_prefix ("/*")) {
					found_start = true;
					break;
				}
				curr_line--;
			} while (curr_line != -1);
			if (found_start) {
				view.buffer.insert (ref iter, previous_line_str.split ("*")[0] + "* ", -1);
				return;
			}
		}
		if (previous_line_stripped.has_prefix ("/*")) {
			info ("Starting multiline-comment");
			var indent1 = previous_line_str.split ("/*")[0] + " * ";
			view.buffer.insert (ref iter, indent1, -1);
			return;
		}
		if (previous_line_stripped.has_prefix ("*/")) {
			info ("Continuing after closed multiline-comment");
			var indent1 = previous_line_str.split ("*/")[0];
			view.buffer.insert (ref iter, indent1.substring (0, indent1.length - 1), -1);
			return;
		}
		// Multiline functioncall(foo,
		// bar
		if (previous_line_stripped.has_suffix (",")) {
			info ("Indent-after-comma");
			// Assume indentation is correct already
			// E.g. in foo(abc,
			// def, // Press Enter
			//// We should be here now
			var indent_part = extract_indent (previous_line_str);
			var other_part = previous_line_str.substring (indent_part.length);
			info ("Divided into `%s' and %s", indent_part, other_part);
			var paren_index = -1;
			for (var i = other_part.length - 1; i != 0; i--) {
				if (other_part[i] == '(') {
					paren_index = i;
					break;
				}
			}
			var new_indent = indent_part;
			if (view.insert_spaces_instead_of_tabs) {
				new_indent += string.nfill (paren_index + 1, ' ');
			} else {
				var spaces_count = (paren_index + 1) % view.tab_width;
				var tab_count = (paren_index + 1 - spaces_count) / view.tab_width;
				new_indent += string.nfill (tab_count, '\t');
				new_indent += string.nfill (spaces_count, ' ');
			}
			info ("New indent: `%s'", new_indent);
			view.buffer.insert (ref iter, new_indent, -1);
			return;
		}
		if (previous_line_stripped.has_suffix ("{")) {
			// Special case for e.g.
			// void foo (int a,
			// int b) {
			//// Don't land here
			//// Land here
			// }
			// It will only go back a one line
			if (line_no >= 1 && !previous_line_stripped.contains ("(") && previous_line_str.contains (")")) {
				warning ("HERE");
				Gtk.TextIter prev_prev_iter;
				view.buffer.get_iter_at_line (out prev_prev_iter, line_no - 2);
				var prev_prev_str = prev_prev_iter.get_text (previous_line_iter);
				if (prev_prev_str.strip ().has_suffix (",")) {
					// Multiline method call/definition
					var reference_indent = extract_indent (prev_prev_str);
					var sub = 3;
					var old = prev_prev_iter;
					while (true) {
						Gtk.TextIter tmp_iter;
						view.buffer.get_iter_at_line (out tmp_iter, line_no - sub);
						var tmp_str = tmp_iter.get_text (old);
						old = tmp_iter;
						sub++;
						var new_indent = extract_indent (tmp_str);
						if (new_indent != reference_indent) {
							var increase = view.insert_spaces_instead_of_tabs ? string.nfill (view.tab_width, ' ') :
							    "\t";
							view.buffer.insert (ref iter, new_indent + increase, -1);
							return;
						}
					}
				}
			}
			var indent1 = view.insert_spaces_instead_of_tabs ? string.nfill (view.tab_width, ' ') : "\t";
			view.buffer.insert (ref iter, extract_indent (previous_line_str) + indent1, -1);
			return;
		}
		view.buffer.insert (ref iter, extract_indent (previous_line_str), -1);
	}

	public bool is_trigger (GtkSource.View view, Gtk.TextIter location, Gdk.ModifierType state, uint keyval) {
		if ((state & (Gdk.ModifierType.SHIFT_MASK | Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SUPER_MASK)) != 0)
			return false;
		return keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter;
	}
}
