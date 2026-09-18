// SPDX-License-Identifier: GPL-3.0-or-later
//
// The Calofin ribbon: one tab, one panel per LAZPANEL category, one
// button per routine filed into it.  Nothing here draws anything --
// exactly like CalofinPalette.vb's Commands tab, a button sends the
// command name it always had and lets the .lsp routine do the work.
// See ui/calofin_ribbon/README.md.

using System;
using System.Collections.Generic;
using System.IO;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media.Imaging;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.Runtime;
using Autodesk.Windows;
using AcadApp = Autodesk.AutoCAD.ApplicationServices.Application;

namespace Calofin.Ribbon
{
    /// <summary>
    /// Loaded on NETLOAD.  Builds the ribbon tab once the ribbon itself
    /// exists -- it does not always exist yet this early in a session --
    /// and rebuilds it, rather than duplicating it, if this assembly is
    /// ever NETLOADed a second time in the same session.
    /// </summary>
    public class RibbonExtensionApplication : IExtensionApplication
    {
        // Fixed, rather than read off CommandCatalog.Groups.Keys: a
        // Dictionary's enumeration order is an implementation detail,
        // not a promise, and this is the order LAZPANEL's own tab strip
        // lists the categories in (tools/check_registry.py's
        // CATEGORIES).
        private static readonly string[] CategoryOrder =
        {
            "Layout", "Points", "Dimensions", "Converters", "Checking",
        };

        private const string TabId = "CALOFIN_RIBBON_TAB";

        public void Initialize()
        {
            if (ComponentManager.Ribbon != null)
            {
                BuildRibbon();
            }
            else
            {
                // The ribbon is not always up yet this early in a
                // session (a bundle demand-loaded at AutoCAD startup,
                // before the default workspace finishes building it).
                // Application.Idle fires repeatedly once the drawing
                // editor is responsive, so it doubles as "try again
                // shortly" without a timer of its own.
                AcadApp.Idle += OnIdle;
            }
        }

        public void Terminate()
        {
        }

        private void OnIdle(object sender, EventArgs e)
        {
            if (ComponentManager.Ribbon == null)
            {
                return;
            }
            AcadApp.Idle -= OnIdle;
            BuildRibbon();
        }

        /// <summary>Rebuilds the tab by hand -- useful after a session
        /// where the ribbon came up before this assembly finished
        /// loading, and the manual escape hatch CALOFIN has as well.</summary>
        [CommandMethod("CALOFINRIBBON")]
        public void ShowRibbon()
        {
            BuildRibbon();
        }

        private static void BuildRibbon()
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
                if (!CommandCatalog.Groups.TryGetValue(
                        category, out CommandCatalog.Entry[] entries))
                {
                    continue;
                }
                tab.Panels.Add(BuildPanel(category, entries));
            }

            tab.IsActive = true;
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

        /// <summary>One panel: the category's icon on the header, and
        /// every one of its commands stacked in a column below it --
        /// RibbonRowBreak is what turns the flat item list into rows,
        /// the way a WPF WrapPanel would if the ribbon framework
        /// exposed one.</summary>
        private static RibbonPanel BuildPanel(
            string category, CommandCatalog.Entry[] entries)
        {
            BitmapImage icon = LoadIcon(category);
            var source = new RibbonPanelSource
            {
                Title = category,
                Image = icon,
            };

            var flow = new RibbonRowPanel();
            foreach (CommandCatalog.Entry entry in entries)
            {
                flow.Items.Add(BuildButton(entry, icon));
                flow.Items.Add(new RibbonRowBreak());
            }
            source.Items.Add(flow);

            return new RibbonPanel { Source = source };
        }

        private static RibbonButton BuildButton(
            CommandCatalog.Entry entry, BitmapImage icon)
        {
            var button = new RibbonButton
            {
                Text = entry.Caption,
                ShowText = true,
                ShowImage = icon != null,
                Size = RibbonItemSize.Standard,
                Orientation = Orientation.Horizontal,
                ToolTip = entry.Command + "  -  " + entry.Caption +
                          "\n" + entry.Blurb,
                CommandParameter = entry.Command,
                CommandHandler = RunCommand.Instance,
            };
            if (icon != null)
            {
                button.Image = icon;
                button.LargeImage = icon;
            }
            return button;
        }

        // -------------------------------------------------------- icons

        private static readonly Dictionary<string, BitmapImage> IconCache =
            new Dictionary<string, BitmapImage>();

        /// <summary>
        /// The category's icon, from icons\&lt;category&gt;.png beside
        /// this assembly -- tools/gen_ribbon_icons.py writes it and the
        /// project copies it on build, the same pattern
        /// ui/calofin_net/Calofin.vbproj uses for assets\bottoms.  A
        /// missing file leaves the button textual rather than failing
        /// the whole tab: a panel with no picture is still a panel.
        /// </summary>
        private static BitmapImage LoadIcon(string category)
        {
            if (IconCache.TryGetValue(category, out BitmapImage cached))
            {
                return cached;
            }

            string dir = Path.GetDirectoryName(
                typeof(RibbonExtensionApplication).Assembly.Location);
            string path = Path.Combine(
                dir ?? string.Empty, "icons",
                category.ToLowerInvariant() + ".png");

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
            IconCache[category] = image;
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
        // the interface and is never raised.
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
