// acady.dcl — Standard Match Results dialog
acady_match : dialog {
  label = "Standard Match Results";
  : list_box {
    key = "matches";
    label = "Candidates (ranked)";
    width = 70;
    height = 10;
    fixed_width = true;
  }
  : boxed_column {
    label = "Details";
    : text { key = "d_name"; width = 66; label = ""; }
    : text { key = "d_src";  width = 66; label = ""; }
    : list_box {
      key = "features";
      label = "Element comparison (candidate vs standard)";
      width = 66;
      height = 7;
      fixed_width = true;
    }
  }
  : row {
    : button { key = "highlight"; label = "&Highlight Match"; }
    : button { key = "zoom";      label = "&Zoom To"; }
    : button { key = "rescan";    label = "&Rescan Standards"; }
  }
  ok_cancel;
}
