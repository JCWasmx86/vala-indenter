/* gtksourcevalaindenter.c
 *
 * Copyright 2022 JCWasmx86 <JCWasmx86@t-online.de>
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
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include <gtksourceview/gtksource.h>
#include <ctype.h>
#include "gtksourcevalaindenter.h"

struct _GtkSource1ValaIndenter
{
    GObject parent_instance;
};

static void indenter_interface_init (GtkSourceIndenterInterface* iface);

G_DEFINE_TYPE_WITH_CODE (GtkSource1ValaIndenter, gtk_source1_vala_indenter, G_TYPE_OBJECT, G_IMPLEMENT_INTERFACE (GTK_SOURCE_TYPE_INDENTER, indenter_interface_init))

GtkSource1ValaIndenter *
gtk_source1_vala_indenter_new (void)
{
    return g_object_new (GTK_SOURCE1_VALA_INDENTER_TYPE, NULL);
}


static void
gtk_source1_vala_indenter_init (GtkSource1ValaIndenter *self)
{
}
static void
gtk_source1_vala_indenter_class_init (GtkSource1ValaIndenterClass *klass)
{
}

// Copied from gtksourceindenter.c
static gboolean
trigger_on_newline (GtkSourceIndenter *self,
                    GtkSourceView     *view,
                    const GtkTextIter *location,
                    GdkModifierType    state,
                    guint              keyval)
{
	if ((state & (GDK_SHIFT_MASK | GDK_CONTROL_MASK | GDK_SUPER_MASK)) != 0)
		return FALSE;

	return (keyval == GDK_KEY_Return || keyval == GDK_KEY_KP_Enter);
}

static gboolean
line_is_a_oneline_block (char *str)
{
    return (g_str_has_prefix (str, "for (")
            || g_str_has_prefix (str, "for(")
            || g_str_has_prefix (str, "if (")
            || g_str_has_prefix (str, "if(")
            || g_str_has_prefix (str, "while (")
            || g_str_has_prefix (str, "while("))
           && !g_str_has_suffix (str, ";")
           && !g_str_has_suffix (str, "{");
}

static gboolean
is_abnormal_indent (GtkSourceView *view,
                    char          *indent)
{
    size_t len;
    if (gtk_source_view_get_insert_spaces_instead_of_tabs (view)) {
        if (strstr (indent, "\t")) {
            return TRUE;
        }
        return strlen (indent) % gtk_source_view_get_tab_width (view);
    } else {
        return !!strstr (indent, " ");
    }
}

static gchar*
extract_indent (gchar *str)
{
    size_t len = strlen (str);
    ssize_t idx = -1;
    for (size_t i = 0; i < len; i++) {
        if (isspace(str[i]) && str[i] != '\n') {
            idx = i;
            continue;
        }
        idx = i;
        break;
    }
    return g_utf8_substring (str, 0, idx == -1 ? 0 : idx);
}

static void vala_indent (GtkSourceIndenter *self,
                         GtkSourceView     *view,
                         GtkTextIter       *location)
{
    int line_no;
    GtkTextIter previous_line_iter;
    GtkTextBuffer *buffer;
    g_autofree char *previous_line_str = NULL;
    g_autofree char *previous_indent = NULL;
    g_autofree char *previous_line_stripped = NULL;

    buffer = gtk_text_view_get_buffer (GTK_TEXT_VIEW (view));
    line_no = gtk_text_iter_get_line (location);
    gtk_text_buffer_get_iter_at_line (buffer, &previous_line_iter, line_no - 1);
    previous_line_str = gtk_text_iter_get_text (&previous_line_iter, location);
    previous_line_stripped = g_strstrip (strdup (previous_line_str));

    if (g_str_has_prefix (previous_line_stripped, "//")) {
        g_debug ("Continuing single-line-comment");
        g_autofree gchar *indent = NULL;
        gchar **strings = NULL;
        g_autofree gchar *full = NULL;
        indent = extract_indent (previous_line_str);
        strings = g_strsplit (previous_line_stripped, "//", 2);
        full = g_strdup_printf ("%s//%s ", indent, strings[0]);
        gtk_text_buffer_insert (buffer, location, full, -1);
        g_strfreev (strings);
        return;
    }
    if (g_str_has_prefix (previous_line_stripped, "*") && !g_str_has_prefix (previous_line_stripped, "*/")) {
        gboolean found_start = FALSE;
        int curr_line;
        GtkTextIter tmp_iter;
        GtkTextIter tmp2_iter;
        curr_line = line_no - 2;
        tmp2_iter = previous_line_iter;
        do {
            g_autofree gchar *text = NULL;
            g_autofree gchar *stripped_text = NULL;
            gtk_text_buffer_get_iter_at_line (buffer, &tmp_iter, curr_line);
            text = gtk_text_iter_get_text (&tmp_iter, &tmp2_iter);
            stripped_text = g_strstrip (strdup (text));
            if (g_str_has_prefix (stripped_text, "/*")) {
                found_start = TRUE;
                break;
            }
            curr_line--;
        } while (curr_line != -1);
        if (found_start) {
            g_debug ("Found start of block-comment");
            gchar **strings = NULL;
            g_autofree gchar *result = NULL;
            strings = g_strsplit (previous_line_str, "*", 2);
            result = g_strdup_printf ("%s* ", strings[0]);
            gtk_text_buffer_insert (buffer, location, result, -1);
            g_strfreev (strings);
            return;
        }
    }
    if (g_str_has_prefix (previous_line_stripped, "/*")) {
        g_debug ("Initializing block-comment");
        gtk_text_buffer_insert (buffer, location, previous_line_str, strstr (previous_line_str, "/*") - previous_line_str);
        gtk_text_buffer_insert (buffer, location, " * ", -1);
        return;
    }

    if (g_str_has_prefix (previous_line_stripped, "*/")) {
        g_debug ("Ending block-comment");
        gtk_text_buffer_insert (buffer, location, previous_line_str, (strstr (previous_line_str, "*/") - previous_line_str) - 1);
        return;
    }
    if (g_str_has_suffix (previous_line_stripped, ",")) {
        g_debug ("Continuing arglist");
        g_autofree char *indent_part = NULL;
        g_autofree char *other_part = NULL;
        int paren_index = -1;
        g_autofree char *new_indent = NULL;
        indent_part = extract_indent (previous_line_str);
        other_part = g_utf8_substring (previous_line_str, strlen (indent_part), -1);
        for (int i = strlen (other_part) - 1; i != 0; i--) {
            if (other_part[i] == '(') {
                paren_index = i;
                break;
            }
        }
        new_indent = indent_part;
        if (gtk_source_view_get_insert_spaces_instead_of_tabs (view)) {
            g_autofree char *nfill = NULL;
            nfill = g_strnfill (paren_index + 1, ' ');
            new_indent = g_strdup_printf ("%s%s", new_indent, new_indent);
        } else {
            gint tab_width;
            gint spaces_count;
            gint tab_count;
            g_autofree char *tabs = NULL;
            g_autofree char *spaces = NULL;
            tab_width = gtk_source_view_get_tab_width (view);
            spaces_count = (paren_index + 1) % tab_width;
            tab_count = (paren_index + 1 - spaces_count) / tab_width;
            tabs = g_strnfill (tab_count, '\t');
            spaces = g_strnfill (spaces_count, ' ');
            new_indent = g_strdup_printf ("%s%s%s", new_indent, tabs, spaces);
        }
        gtk_text_buffer_insert (buffer, location, new_indent, -1);
        return;
    }
    if (g_str_has_suffix (previous_line_stripped, "{")) {
        g_debug ("Found start of block");
        gboolean found_closing_brace;
        g_autofree char *reference_indent = NULL;
        g_autofree char *indent1 = NULL;
        g_autofree char *full = NULL;
        g_autofree char *extension = NULL;
        int text_offset;
        GtkTextIter old;
        int cnter;
        if (line_no >= 2 && !strstr (previous_line_stripped, "(") && strstr (previous_line_stripped, ")")) {
            g_debug ("Found broken up call");
            GtkTextIter prev_prev_iter;
            g_autofree char *prev_prev_str;
            g_autofree char *prev_prev_stripped;
            gtk_text_buffer_get_iter_at_line (buffer, &prev_prev_iter, line_no - 2);
            prev_prev_str = gtk_text_iter_get_text (&prev_prev_iter, &previous_line_iter);
            prev_prev_stripped = g_strstrip (strdup (prev_prev_str));
            if (g_str_has_suffix (prev_prev_stripped, ",")) {
                g_debug ("Found broken up call with comma");
                g_autofree char *reference_indent;
                int sub;
                GtkTextIter old;
                reference_indent = extract_indent (prev_prev_str);
                sub = 3;
                old = prev_prev_iter;
                while (sub <= line_no) {
                    GtkTextIter tmp_iter;
                    g_autofree char *tmp_str;
                    g_autofree char *new_indent;
                    gtk_text_buffer_get_iter_at_line (buffer, &tmp_iter, line_no - sub);
                    tmp_str = gtk_text_iter_get_text (&tmp_iter, &old);
                    old = tmp_iter;
                    sub++;
                    new_indent = extract_indent (tmp_str);
                    if (strcmp (new_indent, reference_indent)) {
                        g_debug ("Found reference indent");
                        g_autofree char *full = NULL;

                        // TODO: Insert braces, too
                        if (gtk_source_view_get_insert_spaces_instead_of_tabs (view)) {
                            g_autofree char *spaces = NULL;
                            spaces = g_strnfill (gtk_source_view_get_tab_width (view), ' ');
                            full = g_strdup_printf ("%s%s", reference_indent, spaces);
                        } else {
                            full = g_strdup_printf ("%s\t", reference_indent);
                        }
                        gtk_text_buffer_insert (buffer, location, full, -1);
                        text_offset = gtk_text_iter_get_offset (location);
                        gtk_text_buffer_insert (buffer, location, "\n", -1);
                        gtk_text_buffer_insert (buffer, location, reference_indent, -1);
                        gtk_text_buffer_insert (buffer, location, "}", -1);
                        gtk_text_iter_set_offset (location, text_offset);
                        return;
                    }
                }
                goto end_block;
            }
        }
        found_closing_brace = false;
        reference_indent = extract_indent (previous_line_str);
        if (is_abnormal_indent (view, reference_indent)) {
            g_free (reference_indent);
            GtkTextIter old;
            int backwards;
            backwards = 2;
            old = previous_line_iter;
            while (line_no > backwards) {
                GtkTextIter tmp;
                g_autofree char *tmp_str = NULL;
                g_autofree char *tmp_indent = NULL;
                gtk_text_buffer_get_iter_at_line (buffer, &tmp, line_no - backwards);
                tmp_str = gtk_text_iter_get_text (&tmp, &old);
                old = tmp;
                tmp_indent = extract_indent (tmp_str);
                if (!is_abnormal_indent (view, tmp_indent)) {
                    reference_indent = strdup (tmp_indent);
                    break;
                }
                backwards++;
            }
        }
        old = previous_line_iter;
        cnter = 0;
        while (line_no + cnter <= gtk_text_buffer_get_line_count (buffer)) {
            if (cnter <= 1) {
                gtk_text_buffer_get_iter_at_line (buffer, &old, line_no + cnter);
                cnter++;
                continue;
            }
            GtkTextIter next_line;
            g_autofree char *str;
            g_autofree char *str_stripped = NULL;
            g_autofree char *new_indent = NULL;
            gtk_text_buffer_get_iter_at_line (buffer, &next_line, line_no + cnter);
            str = gtk_text_iter_get_text (&old, &next_line);
            str_stripped = g_strstrip (g_strdup (str));
            old = next_line;
            new_indent = extract_indent (str);
            if (!strcmp (new_indent, reference_indent) && g_str_has_prefix (str_stripped, "}")) {
                found_closing_brace = TRUE;
                break;
            } else if (strlen (new_indent) < strlen (reference_indent)) {
                break;
            } else if (!strcmp (new_indent, reference_indent)) {
                break;
            }
            cnter++;
        }
        if (gtk_source_view_get_insert_spaces_instead_of_tabs (view)) {
            indent1 = g_strnfill (gtk_source_view_get_tab_width (view), ' ');
        } else {
            indent1 = g_strdup ("\t");
        }
        if (found_closing_brace) {
            g_autofree char *full;
            g_debug ("Found closing brace");
            full = g_strdup_printf ("%s%s", reference_indent, indent1);
            gtk_text_buffer_insert (buffer, location, full, -1);
            return;
        }
        g_debug ("Completing block");
        full = g_strdup_printf ("%s%s", reference_indent, indent1);
        gtk_text_buffer_insert (buffer, location, full, -1);
        text_offset = gtk_text_iter_get_offset (location);
        extension = g_strdup_printf ("\n%s}", reference_indent);
        gtk_text_buffer_insert (buffer, location, extension, -1);
        gtk_text_iter_set_offset (location, text_offset);
        return;
    } else if (line_is_a_oneline_block (previous_line_stripped)) {
        g_debug ("Oneline block begin");
        g_autofree char *indent;
        g_autofree char *indent1;
        indent = extract_indent (previous_line_str);
        if (gtk_source_view_get_insert_spaces_instead_of_tabs (view)) {
            indent1 = g_strnfill (gtk_source_view_get_tab_width (view), ' ');
        } else {
            indent1 = g_strdup ("\t");
        }
        gtk_text_buffer_insert (buffer, location, indent, -1);
        gtk_text_buffer_insert (buffer, location, indent1, -1);
        return;
    }
end_block:
    if (!g_str_has_prefix (previous_line_stripped, "{")) {
        g_debug ("Fixing up after one-line block");
        GtkTextIter prev_prev_iter;
        g_autofree char *prev_prev_str;
        g_autofree char *prev_prev_stripped;
        gtk_text_buffer_get_iter_at_line (buffer, &prev_prev_iter, line_no - 2);
        prev_prev_str = gtk_text_iter_get_text (&prev_prev_iter, &previous_line_iter);
        prev_prev_stripped = g_strstrip (strdup (prev_prev_str));
        if (line_is_a_oneline_block (prev_prev_stripped) && *previous_line_stripped && !g_str_has_prefix (prev_prev_stripped, "{")) {
            g_autofree char *indent;
            indent = extract_indent (prev_prev_str);
            gtk_text_buffer_insert (buffer, location, indent, -1);
            return;
        }
    }
    if (strstr (previous_line_stripped, "default:")
        || (g_str_has_suffix (previous_line_stripped, ":") && strstr (previous_line_stripped, "case "))) {
        g_debug ("Fixing label");
        g_autofree char *indent;
        g_autofree char *indent1;
        indent = extract_indent (previous_line_str);
        if (gtk_source_view_get_insert_spaces_instead_of_tabs (view)) {
            indent1 = g_strnfill (gtk_source_view_get_tab_width (view), ' ');
        } else {
            indent1 = g_strdup ("\t");
        }
        gtk_text_buffer_insert (buffer, location, indent, -1);
        gtk_text_buffer_insert (buffer, location, indent1, -1);
        return;
    }
    if (!gtk_source_view_get_insert_spaces_instead_of_tabs (view)) {
        g_debug ("Rounding up to tabs");
        g_autofree char *indent;
        size_t idx;
        gboolean disable;
        indent = extract_indent (previous_line_str);
        idx = strlen (indent) - 1;
        disable = g_str_has_suffix (previous_line_stripped, ";");
        while (strlen (indent) && idx && indent[idx] == ' ' && disable) {
            idx--;
        }
        gtk_text_buffer_insert (buffer, location, indent, idx + 1);
        return;
    }
    g_debug ("Rounding up to spaces");
    previous_indent = extract_indent (previous_line_str);
    if (g_str_has_suffix (previous_line_stripped, ";")) {
        size_t n = 0;
        n = strlen (previous_indent);
        previous_indent[n - (n % gtk_source_view_get_tab_width (view))] = '\0';
    }
    gtk_text_buffer_insert (buffer, location, previous_indent, -1);
}
static void
indenter_interface_init (GtkSourceIndenterInterface *iface)
{
    iface->is_trigger = trigger_on_newline;
	iface->indent = vala_indent;
}
