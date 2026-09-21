// SPDX-License-Identifier: GPL-3.0-or-later
//
// The Calofin ribbon: one tab, one panel per LAZPANEL category, and a
// button per routine -- with a routine's VARIANTS (POOLCOVER under
// POOL, XFTRECONV under XFTCONV) on that routine's dropdown rather
// than beside it.  Nothing here draws anything: exactly like
// CalofinPalette.vb's Commands tab, a button sends the command name it
// always had and lets the .lsp routine do the work.
// See ui/calofin_ribbon/README.md.

using System;
using System.Collections.Generic;
using System.IO;
using System.Windows.Controls;
using System.Windows.Media.Imaging;
using System.Windows.Input;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.Runtime;
using Autodesk.Windows;
using AcadApp = Autodesk.AutoCAD.ApplicationServices.Application;

namespace Calofin.Ribbon
{
    /// <summary>
    /// Loaded on NETLOAD.  Builds the ribbon tab once the ribbon itself
    /// exists -- it does not always exist yet this early in a session --
    /// rebuilds it rather than duplicating it if this assembly is
    /// NETLOADed a second time, and puts it back when a workspace
    /// switch takes it away.
    /// </summary>
    public class RibbonExtensionApplication : IExtensionApplication
    {
        // Fixed, rather than read off CommandCatalog.Panels.Keys: a
        // Dictionary's enumeration order is an implementation detail,
        // not a promise, and this is the order LAZPANEL's own tab strip
        // lists the categories in (tools/check_registry.py's
        // CATEGORIES).
        private static readonly string[] CategoryOrder =
        {
            "Layout", "Points", "Dimensions", "Converters", "Checking",
        };

        private const string TabId = "CALOFIN_RIBBON_TAB";

        // An AutoCAD panel is three rows of standard-size items tall.
        // This used to put a RibbonRowBreak after EVERY item, which is
        // not "wrap" -- it is one button per row -- so Layout asked for
        // 26 rows in a panel that can show three, and the other 23 were
        // simply not on the screen.  Three to a column, and a fresh
        // RibbonRowPanel per column, is how a ribbon panel is built.
        private const int RowsPerColumn = 3;

        public void Initialize()
        {
            AcadApp.SystemVariableChanged += OnSystemVariableChanged;
            ScheduleBuild();
        }

        public void Terminate()
        {
            AcadApp.SystemVariableChanged -= OnSystemVariableChanged;
            AcadApp.Idle -= OnIdle;
        }

        /// <summary>
        /// A workspace switch rebuilds the ribbon out of the CUI -- and
        /// a tab added through the API is not IN the CUI, so ours is
        /// gone with it.  Nothing about that looks like a failure: the
        /// drafter picks a different workspace and the toolset's tab
        /// has quietly stopped existing.  So put it back.
        /// </summary>
        private static void OnSystemVariableChanged(
            object sender, SystemVariableChangedEventArgs e)
        {
            if (string.Equals(e.Name, "WSCURRENT",
                              StringComparison.OrdinalIgnoreCase))
            {
                ScheduleBuild();
            }
        }

        /// <summary>Build at the next idle rather than here and now.
        /// The ribbon is not up yet during a startup load, and during a
        /// workspace switch it is mid-rebuild; Application.Idle fires
        /// once the editor is responsive, which is after both.</summary>
        private static void ScheduleBuild()
        {
            AcadApp.Idle -= OnIdle;     // never queued twice
            AcadApp.Idle += OnIdle;
        }

        private static void OnIdle(object sender, EventArgs e)
        {
            if (ComponentManager.Ribbon == null)
            {
                return;                 // not up yet; idle fires again
            }
            AcadApp.Idle -= OnIdle;
            BuildRibbon(activate: false);
        }

        /// <summary>Rebuilds the tab by hand -- the escape hatch for a
        /// session where the ribbon came up before this assembly
        /// finished loading, and the one place the tab is brought to
        /// the front, because here somebody asked for it.</summary>
        [CommandMethod("CALOFINRIBBON")]
        public void ShowRibbon()
        {
            BuildRibbon(activate: true);
        }

        /// <param name="activate">Make the tab the current one.  False
        /// on every automatic path: this assembly is demand-loaded at
        /// AutoCAD startup, and a tab that makes itself current there
        /// means every session opens on Calofin instead of Home.</param>
        private static void BuildRibbon(bool activate)
        {
            RibbonControl ribbon = ComponentManager.Ribbon;
            if (ribbon == null)
            {
                return;
            }

            RibbonTab tab = FindTab(ribbon, TabId);
            if (tab == null)
            {
                tab = new RibbonTab { Title = "Calofin", Id = TabId };
                ribbon.Tabs.Add(tab);
            }
            else
            {
                tab.Panels.Clear();
            }

            foreach (string category in CategoryOrder)
            {
                if (!CommandCatalog.Panels.TryGetValue(
                        category, out CommandCatalog.Item[] items))
                {
                    continue;
                }
                tab.Panels.Add(BuildPanel(category, items));
            }

            if (activate)
            {
                tab.IsActive = true;
            }
        }

        private static RibbonTab FindTab(RibbonControl ribbon, string id)
        {
            foreach (RibbonTab t in ribbon.Tabs)
            {
                if (t.Id == id)
                {
                    return t;
                }
            }
            return null;
        }

        /// <summary>
        /// One panel.  The large routines lead it, full height, with
        /// their glyph at 32 and the command under it; the rest follow
        /// three to a column, wearing the same glyph at 16 beside the
        /// name where one was drawn for them and plain text where none
        /// was.
        ///
        /// Neither is decided here -- Item.IsLarge and Item.HasIcon come
        /// off gen_ui_data.FEATURED, the same table gen_ribbon_icons.py
        /// draws from, so a button and the picture on it cannot come
        /// apart.
        /// </summary>
        private static RibbonPanel BuildPanel(
            string category, CommandCatalog.Item[] items)
        {
            // Title only.  RibbonPanelSource has no image of any kind --
            // tools/check_netapi.py reads that out of AdWindows.dll, and
            // it is where the category icon was wrongly hung first.  The
            // picture a panel shows is the PANEL's, below.
            var source = new RibbonPanelSource { Title = category };

            foreach (CommandCatalog.Item item in items)
            {
                if (item.IsLarge)
                {
                    source.Items.Add(BuildItem(item));
                }
            }

            // The rest, in columns of three.  Each column is its own
            // RibbonRowPanel: RibbonPanelSource.Items lays out across
            // the panel, a RibbonRowPanel stacks down it, and a
            // RibbonRowBreak between two items is what makes the second
            // start a new row rather than sit beside the first.
            RibbonRowPanel column = null;
            int inColumn = 0;
            foreach (CommandCatalog.Item item in items)
            {
                if (item.IsLarge)
                {
                    continue;
                }
                if (column == null)
                {
                    column = new RibbonRowPanel();
                    inColumn = 0;
                }
                if (inColumn > 0)
                {
                    column.Items.Add(new RibbonRowBreak());
                }
                column.Items.Add(BuildItem(item));
                if (++inColumn == RowsPerColumn)
                {
                    source.Items.Add(column);
                    column = null;
                }
            }
            if (column != null)
            {
                source.Items.Add(column);
            }

            // CollapsedPanelImage is what AutoCAD draws when the strip
            // runs out of room and the panel folds into one button --
            // which, with five panels this wide, is a state Checking and
            // Converters will often be in.
            return new RibbonPanel
            {
                Source = source,
                CollapsedPanelImage = LoadIcon(
                    "cat-" + category.ToLowerInvariant() + "-32.png"),
            };
        }

        /// <summary>A routine's button: plain when it has no variants,
        /// a split button carrying them when it has.</summary>
        private static RibbonItem BuildItem(CommandCatalog.Item item)
        {
            // Only a featured routine has a glyph of its own, and its
            // variants share it: POOLCOVER is POOL with one answer
            // changed, so POOL's picture is the right picture for it.
            bool large = item.IsLarge;
            string stem = item.HasIcon
                ? "cmd-" + item.Primary.Command.ToLowerInvariant()
                : null;
            BitmapImage small = stem == null ? null : LoadIcon(stem + "-16.png");
            BitmapImage big = stem == null ? null : LoadIcon(stem + "-32.png");

            RibbonButton primary = BuildButton(item.Primary, large, small, big);
            if (item.Variants.Length == 0)
            {
                return primary;
            }

            var split = new RibbonSplitButton
            {
                Text = item.Primary.Command,
                ShowText = true,
                ShowImage = big != null,
                Size = large ? RibbonItemSize.Large : RibbonItemSize.Standard,
                Orientation = large ? Orientation.Vertical
                                    : Orientation.Horizontal,
                IsSplit = true,
                // The face follows the last pick, the way AutoCAD's own
                // flyouts do: a drafter who works in cover sheets all
                // afternoon reaches for POOLCOVER once and then it is
                // the button.
                IsSynchronizedWithCurrentItem = true,
            };
            if (big != null)
            {
                split.Image = small ?? big;
                split.LargeImage = big;
            }

            split.Items.Add(primary);
            foreach (CommandCatalog.Entry variant in item.Variants)
            {
                // Built at the SPLIT BUTTON's size, not at Standard:
                // with IsSynchronizedWithCurrentItem the picked variant
                // becomes the face, and a face built small inside a
                // large button is a button that changes size when it is
                // used.
                split.Items.Add(BuildButton(variant, large, small, big));
            }
            split.Current = primary;
            return split;
        }

        private static RibbonButton BuildButton(
            CommandCatalog.Entry entry, bool large,
            BitmapImage small, BitmapImage big)
        {
            var button = new RibbonButton
            {
                // The COMMAND on the face, not the caption.  A ribbon
                // button is roughly a word wide, and LAZPANEL's captions
                // are sentences -- "Pool from a filled-in chart" is a
                // fine thing to read in a list and an unaffordable thing
                // to put on a strip shared with every other tab AutoCAD
                // has.  The caption is the tooltip's title, one hover
                // away, and the command name is what the drafter types
                // anyway.
                Text = entry.Command,
                ShowText = true,
                ShowImage = big != null,
                Size = large ? RibbonItemSize.Large : RibbonItemSize.Standard,
                Orientation = large ? Orientation.Vertical
                                    : Orientation.Horizontal,
                ToolTip = new RibbonToolTip
                {
                    Command = entry.Command,
                    Title = entry.Caption,
                    Content = entry.Blurb,
                    IsHelpEnabled = false,
                },
                CommandParameter = entry.Command,
                CommandHandler = RunCommand.Instance,
            };
            if (big != null)
            {
                button.Image = small ?? big;
                button.LargeImage = big;
            }
            return button;
        }

        // -------------------------------------------------------- icons

        private static readonly Dictionary<string, BitmapImage> IconCache =
            new Dictionary<string, BitmapImage>();

        /// <summary>
        /// One icon, by file name, from icons\ beside this assembly --
        /// tools/gen_ribbon_icons.py writes them and the project copies
        /// them on build, the same pattern ui/calofin_net/Calofin.vbproj
        /// uses for assets\bottoms.  A missing file leaves the button
        /// textual rather than failing the whole tab: a button with no
        /// picture is still a button, and a tab that threw is not a tab.
        /// </summary>
        private static BitmapImage LoadIcon(string fileName)
        {
            if (IconCache.TryGetValue(fileName, out BitmapImage cached))
            {
                return cached;
            }

            string dir = Path.GetDirectoryName(
                typeof(RibbonExtensionApplication).Assembly.Location);
            string path = Path.Combine(dir ?? string.Empty, "icons", fileName);

            BitmapImage image = null;
            if (File.Exists(path))
            {
                try
                {
                    image = new BitmapImage();
                    image.BeginInit();
                    image.CacheOption = BitmapCacheOption.OnLoad;
                    image.UriSource = new Uri(path, UriKind.Absolute);
                    image.EndInit();
                    image.Freeze();
                }
                catch
                {
                    image = null;
                }
            }
            IconCache[fileName] = image;
            return image;
        }
    }

    /// <summary>
    /// One ICommand shared by every ribbon button. CommandParameter
    /// carries the AutoCAD command name to run, exactly as
    /// CalofinPalette.RunCommand does from the Commands tab -- queued
    /// on the active document rather than run in place, because a
    /// command cannot be started while the ribbon's own click handler
    /// still holds the thread.
    /// </summary>
    public sealed class RunCommand : ICommand
    {
        public static readonly RunCommand Instance = new RunCommand();

        private RunCommand()
        {
        }

        // A ribbon button's enabled state never changes here -- CanExecute
        // is asked once, at build time -- so the event exists to satisfy
        // the interface and is never raised.  Unlike the palette, this
        // surface does not grey out a command the session has not
        // loaded; see README.md, "what this does not do".
        public event EventHandler CanExecuteChanged
        {
            add { }
            remove { }
        }

        public bool CanExecute(object parameter)
        {
            return AcadApp.DocumentManager.MdiActiveDocument != null;
        }

        public void Execute(object parameter)
        {
            Document doc = AcadApp.DocumentManager.MdiActiveDocument;
            if (doc == null || !(parameter is string command))
            {
                return;
            }
            doc.SendStringToExecute("_." + command + "\n", true, false, true);
        }
    }
}
