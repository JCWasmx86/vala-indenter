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
		w.set_size_request (600, 400);
		var gsv = new GtkSource.View ();
		var sc = new Gtk.ScrolledWindow ();
		sc.child = gsv;
		w.child = sc;
		// gsv.indenter = new ValaIndenter ();
		gsv.indenter = new GtkSource1.ValaIndenter ();
		gsv.set_auto_indent (true);
		gsv.space_drawer.enable_matrix = true;
		((GtkSource.Buffer) gsv.buffer).set_style_scheme (GtkSource.StyleSchemeManager.get_default ().get_scheme (
		                                                                                                          "Adwaita-dark"));
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
		if (previous_line_stripped.has_suffix (",")) {
			info ("Indent-after-comma");
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
		// Increase indentation, but be wary of multi-line method calls/definitions/etc.
		if (previous_line_stripped.has_suffix ("{")) {
			if (line_no >= 1 && !previous_line_stripped.contains ("(") && previous_line_str.contains (")")) {
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
			var found_closing_brace = false;
			var reference_indent = extract_indent (previous_line_str);
			var old = iter;
			var cnter = 0;
			while (line_no + cnter <= view.buffer.get_line_count ()) {
				Gtk.TextIter next_line;
				view.buffer.get_iter_at_line (out next_line, line_no + cnter);
				cnter++;
				var str = old.get_text (next_line);
				info (">> `%s'", str);
				old = next_line;
				if (extract_indent (str) == reference_indent && str.strip ().has_prefix ("}")) {
					found_closing_brace = true;
					break;
				} else if (extract_indent (str).length < reference_indent.length) {
					found_closing_brace = false;
					break;
				}
			}
			var indent1 = view.insert_spaces_instead_of_tabs ? string.nfill (view.tab_width, ' ') : "\t";
			if (found_closing_brace) {
				view.buffer.insert (ref iter, reference_indent + indent1, -1);
				return;
			}
			info ("Found no closing brace");
			view.buffer.insert (ref iter, reference_indent + indent1, -1);
			var tmp = iter.get_offset ();
			info ("%d", iter.get_offset ());
			view.buffer.insert (ref iter, "\n" + reference_indent + "}", -1);
			info ("%d", iter.get_offset ());
			iter.set_offset (tmp);
			info ("%d", iter.get_offset ());
			view.buffer.get_iter_at_offset (out iter, tmp);
			return;
		} else if ((previous_line_stripped.has_prefix ("for (")
		            || previous_line_stripped.has_prefix ("for(")
		            || previous_line_stripped.has_prefix ("if (")
		            || previous_line_stripped.has_prefix ("if(")
		            || previous_line_stripped.has_prefix ("while (")
		            || previous_line_stripped.has_prefix ("while("))
		           && !previous_line_stripped.has_suffix (";")) {
			// Oneline for-Loops/if-Statements
			var indent1 = view.insert_spaces_instead_of_tabs ? string.nfill (view.tab_width, ' ') : "\t";
			view.buffer.insert (ref iter, extract_indent (previous_line_str) + indent1, -1);
			return;
		}
		// Go back after oneline statements
		if (!previous_line_stripped.has_suffix ("{")) {
			Gtk.TextIter prev_prev_iter;
			view.buffer.get_iter_at_line (out prev_prev_iter, line_no - 2);
			var prev_prev_str = prev_prev_iter.get_text (previous_line_iter);
			var prev_prev_str1 = prev_prev_str.strip ();
			if ((prev_prev_str1.has_prefix ("for (")
			     || prev_prev_str1.has_prefix ("for(")
			     || prev_prev_str1.has_prefix ("if (")
			     || prev_prev_str1.has_prefix ("if(")
			     || (prev_prev_str1.has_prefix ("while (") && !prev_prev_str1.has_suffix (";"))
			     || (prev_prev_str1.has_prefix ("while(") && !prev_prev_str1.has_suffix (";")))
			    && previous_line_stripped != ""
			    && !prev_prev_str1.has_suffix ("{")) {
				info ("Continuing after one-line stmt");
				var old_indent = extract_indent (prev_prev_str);
				view.buffer.insert (ref iter, old_indent, -1);
				return;
			}
		}
		if (previous_line_stripped.contains ("default:") || (previous_line_stripped.has_suffix (":") &&
		                                                     previous_line_stripped.contains ("case "))) {
			var indent1 = view.insert_spaces_instead_of_tabs ? string.nfill (view.tab_width, ' ') : "\t";
			view.buffer.insert (ref iter, extract_indent (previous_line_str) + indent1, -1);
			return;
		}
		if (!view.insert_spaces_instead_of_tabs) {
			var indent = extract_indent (previous_line_str);
			while (indent.has_suffix (" ") && previous_line_stripped.has_suffix (";"))
				indent = indent.substring (0, indent.length - 1);
			view.buffer.insert (ref iter, indent, -1);
			return;
		}
		var indent = extract_indent (previous_line_str);
		if (previous_line_stripped.has_suffix (";")) {
			var n = indent.length;
			indent = indent.substring (0, n - (n % view.tab_width));
		}
		view.buffer.insert (ref iter, indent, -1);
	}

	public bool is_trigger (GtkSource.View view, Gtk.TextIter location, Gdk.ModifierType state, uint keyval) {
		if ((state & (Gdk.ModifierType.SHIFT_MASK | Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SUPER_MASK)) != 0)
			return false;
		return keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter;
	}
}
