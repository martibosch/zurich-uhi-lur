"""Plotting utils."""

from collections.abc import Iterable, Mapping

import contextily as cx
import geopandas as gpd
import matplotlib as mpl
import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns

# for type annotations
KwargsType = Mapping | None

# ACHTUNG: the article figures are drawn at the size at which the article prints them,
# so that LaTeX applies no scaling when including them and the font sizes below are the
# printed ones. The widths follow the geometry of `reports/article.tex`: the text block,
# and the text block widened into the left margin by `adjustwidth{-.4\textwidth}`
TEXT_WIDTH = 5.25  # in
WIDE_TEXT_WIDTH = 1.4 * TEXT_WIDTH  # in
# sub-figures whose (a)/(b) label sits beside the panel reserve a 1.5em box for it,
# i.e., 15 pt at the article's 10 pt font size
SUBFIGURE_LABEL_WIDTH = 15 / 72.27  # in

# printed font sizes, within the 8-12 pt range that PLOS asks for text in figures
FONT_SIZE = 9  # pt, axis labels and titles
SMALL_FONT_SIZE = 8  # pt, tick labels, legends and annotations

STYLE_RC = {
    "font.size": FONT_SIZE,
    "axes.labelsize": FONT_SIZE,
    "axes.titlesize": FONT_SIZE,
    "figure.titlesize": FONT_SIZE,
    "xtick.labelsize": SMALL_FONT_SIZE,
    "ytick.labelsize": SMALL_FONT_SIZE,
    "legend.fontsize": SMALL_FONT_SIZE,
    "legend.title_fontsize": FONT_SIZE,
    "axes.linewidth": 0.8,
    "lines.linewidth": 1.2,
    "lines.markersize": 4,
    "xtick.major.width": 0.8,
    "ytick.major.width": 0.8,
    "xtick.major.size": 3,
    "ytick.major.size": 3,
    "xtick.minor.width": 0.6,
    "ytick.minor.width": 0.6,
    # all four spines are kept (seaborn's "ticks" style), i.e., no despining
    "axes.spines.top": True,
    "axes.spines.right": True,
    "savefig.dpi": 300,
    # embed TrueType fonts so that the text of the PDF figures stays editable
    "pdf.fonttype": 42,
}


def set_style() -> None:
    """Apply the article figure style to all subsequent figures.

    Sets the seaborn "ticks" style, which keeps all four spines, with the font sizes and
    line widths of `STYLE_RC`. Figures drawn at their printed width (`TEXT_WIDTH` or
    `WIDE_TEXT_WIDTH`, or a fraction thereof for sub-figures) then print with the same
    text size across the article.
    """
    sns.set_theme(style="ticks", rc=STYLE_RC)


def label_panels(axes: Iterable[mpl.axes.Axes]) -> None:
    """Label each panel with a letter in parentheses at its top left.

    The letters are set as left-aligned axes titles, so that the constrained layout
    reserves space for them, and they match the "(a)", "(b)"... sub-figure references
    of the article captions.

    Parameters
    ----------
    axes : iterable of matplotlib.axes.Axes
        Axes to label, in the order of the letters.
    """
    for i, ax in enumerate(axes):
        ax.set_title(f"({chr(ord('a') + i)})", loc="left", fontsize=FONT_SIZE)


def comparison_lineplot(
    ts_df_dict: Mapping[str, pd.DataFrame],
    *,
    value_label: str = "T (°C)",
    station_label: str = "station_id",
    source_label: str = "Source",
    **lineplot_kwargs: KwargsType,
) -> mpl.axes.Axes:
    """Lineplot comparing CWS and official stations time series.

    Parameters
    ----------
    ts_df_dict : mapping of str to pandas.DataFrame
        Dictionary of time series dataframes, where the keys are the source labels and
        the values are the time series data frames of measurements (rows) for each
        station (columns)
    value_label : str, optional
        Label for the values, by default "T" (for temperature).
    station_label : str, optional
        Label for the stations, by default "station_id".
    source_label : str, optional
        Label for the source, by default "source".
    lineplot_kwargs : mapping, optional
        Keyword arguments to pass to `seaborn.lineplot`.

    Returns
    -------
    matplotlib.axes.Axes
        Axes of the plot.

    """
    return sns.lineplot(
        data=pd.concat(
            [
                ts_df_dict[source]
                .reset_index()
                .melt(id_vars="time", var_name=station_label, value_name=value_label)
                .assign(**{source_label: source})
                for source in ts_df_dict
            ],
            ignore_index=True,
        ),
        x="time",
        y=value_label,
        hue=source_label,
        **lineplot_kwargs,
    )


def comparison_lineplots(
    ts_df_dict: Mapping[str, pd.DataFrame],
    *,
    value_label: str = "T (°C)",
    station_label: str = "station_id",
    source_label: str = "Source",
    **facetgrid_kwargs: KwargsType,
) -> sns.FacetGrid:
    """Lineplots comparing CWS and official stations time series.

    Parameters
    ----------
    ts_df_dict : mapping of str to pandas.DataFrame
        Dictionary of time series dataframes, where the keys are the source labels and
        the values are the time series data frames of measurements (rows) for each
        station (columns), multi-indexed by the heatwave identifier and the time.
    value_label, station_label, source_label : str, optional
        Label for the values, stations and source, by default "T (°C)", "station_id" and
        "Source" respectively.
    facetgrid_kwargs : mapping, optional
        Keyword arguments to pass to `seaborn.FacetGrid`.

    Returns
    -------
    fig : matplotlib.figure.Figure
        Figure of the plot.

    """
    if facetgrid_kwargs is None:
        _facetgrid_kwargs = {}
    else:
        _facetgrid_kwargs = facetgrid_kwargs.copy()
        _ = _facetgrid_kwargs.pop("sharex", None)
    g = sns.FacetGrid(
        pd.concat(
            [
                ts_df_dict[source]
                .reset_index()
                .melt(
                    id_vars=["time", "heatwave"],
                    var_name="station_id",
                    value_name=value_label,
                )
                .assign(**{source_label: source})
                for source in ts_df_dict
            ]
        ),
        col="heatwave",
        hue=source_label,
        sharex=False,
        **_facetgrid_kwargs,
    )
    g.map(sns.lineplot, "time", value_label)
    g.set_xticklabels(rotation=45)
    for ax in g.axes.flat:
        ax.xaxis.set_major_formatter(mdates.DateFormatter("%d-%m"))
    g.add_legend()

    return g


def hourly_lineplot(
    ts_df: pd.DataFrame,
    *,
    value_label: str = "T",
    ax: mpl.axes.Axes = None,
    legend: bool = True,
) -> mpl.axes.Axes:
    """Plot of hourly time series of a variable for each heatwave."""
    if ax is None:
        _, ax = plt.subplots()
    # y = ts_df.columns[0]
    for heatwave, heatwave_ts_df in ts_df.groupby(level="heatwave"):
        heatwave_ts_df = heatwave_ts_df.stack(future_stack=True).reset_index(
            name=value_label
        )
        sns.lineplot(
            # heatwave_ts_df.assign(
            #     **{"hour": heatwave_ts_df.index.get_level_values("time").hour}
            # ),
            heatwave_ts_df.assign(**{"hour": heatwave_ts_df["time"].dt.hour}),
            x="hour",
            # y=y,
            y=value_label,
            ax=ax,
            label=heatwave,
            legend=legend,
        )

    return ax


def plot_map_by_var(
    station_gser: gpd.GeoSeries,
    var_ser: pd.Series,
    *,
    var_label: str = None,
    legend: bool = True,
    edgecolor: str = "black",
    attribution: str | bool = False,
    set_axis_off: bool = True,
    add_basemap_kws: dict | None = None,
    **plot_kws: KwargsType,
) -> mpl.axes.Axes:
    """Plot stations by variable.

    Parameters
    ----------
    station_gser : gpd.GeoSeries
        GeoSeries of stations.
    var_ser : pd.Series
        Series of variable values.
    var_label : str, optional
        Label given the variable of `var_ser`. If None, the name of `var_ser` is used.
        If None and `var_ser` has no name, "var" is used.
    legend : bool, optional
        Whether to add a legend, by default True.
    edgecolor : str, optional
        Color of the edges, by default "black".
    attribution : str | bool, optional
        Attribution of the basemap, by default False.
    set_axis_off : bool, optional
        Whether to set the axis off, by default True.
    add_basemap_kws : dict, optional
        Keyword arguments to pass to `contextily.add_basemap`, by default None.
    plot_kws : dict, optional
        Keyword arguments to pass to `geopardas.GeoDataFrame.plot`, by default None.

    Returns
    -------
    matplotlib.axes.Axes
        Axes of the plot.

    """
    if plot_kws is None:
        plot_kws = {}
    if add_basemap_kws is None:
        add_basemap_kws = {}
    if var_label is None:
        var_label = var_ser.name
    if var_label is None:
        var_label = "var"
    ax = gpd.GeoDataFrame({var_label: var_ser}, geometry=station_gser).plot(
        var_label, legend=legend, edgecolor=edgecolor, **plot_kws
    )
    cx.add_basemap(ax, crs=station_gser.crs, attribution=attribution, **add_basemap_kws)
    if set_axis_off:
        ax.set_axis_off()
    return ax


def compare_maps(
    stations_gdf: gpd.GeoDataFrame,
    var_ser: pd.Series,
    *,
    var_label: str = None,
    by_col: str = "source",
    figwidth: float = None,
    figheight: float = None,
    vmin: float = None,
    vmax: float = None,
    cmap: str = "coolwarm",
    legend: bool = True,
    region_gdf: gpd.GeoDataFrame | None = None,
    **region_plot_kwargs: KwargsType,
) -> mpl.figure.Figure:
    """Side-by-side plot of maps of a variable.

    Parameters
    ----------
    stations_gdf : gpd.GeoDataFrame
        GeoDataFrame of stations.
    var_ser : pd.Series
        Series of variable values.
    var_label : str, optional
        Label given the variable of `var_ser`. If None, the name of `var_ser` is used.
        If None and `var_ser` has no name, "var" is used.
    by_col : str, optional
        Column of `stations_gdf` to group by, by default "source".
    figwidth, figheight : float, optional
        Width and height of the figure. If None, the default values from the matplotlib
        configuration are used.
    vmin, vmax : float, optional
        Minimum and maximum values of the color scale, by default None. If None, the
        minimum and maximum values of `var_ser` are used.
    cmap : str, optional
        Colormap to use, by default "coolwarm".
    legend : bool, optional
        Whether to add a legend, by default True.

    Returns
    -------
    mpl.figure.Figure
        Figure of the plot.

    """
    if figwidth is None:
        figwidth, _ = plt.rcParams["figure.figsize"]
    if figheight is None:
        _, figheight = plt.rcParams["figure.figsize"]

    # heatwaves = ts_df.index.get_level_values("heatwave").unique()
    # station_T_mean_gdf = stations_gdf[["source", "geometry"]].assign(
    #     T_mean=ts_df.groupby(station_id_col)["T"].mean()
    # )
    if var_label is None:
        var_label = var_ser.name
    if var_label is None:
        var_label = "var"
    station_var_gdf = stations_gdf[[by_col, "geometry"]].assign(**{var_label: var_ser})

    station_var_gb = station_var_gdf.groupby(by_col, sort=False)
    num_cols = len(station_var_gb)
    fig, axes = plt.subplots(
        1,
        num_cols,
        figsize=(figwidth * num_cols, figheight),
        layout="constrained",
    )

    # common legend
    if vmin is None:
        vmin = station_var_gdf[var_label].min()
    if vmax is None:
        vmax = station_var_gdf[var_label].max()

    # common extent
    if region_gdf is not None:
        _ = region_plot_kwargs.pop("ax", None)
        for ax in axes:
            region_gdf.plot(ax=ax, **region_plot_kwargs)

        # extent = region_gdf.buffer(100).total_bounds
        extent = region_gdf.total_bounds
    else:
        extent = station_var_gdf.total_bounds

    for (source, source_gdf), ax in zip(station_var_gb, axes):
        ax.set_xlim(extent[[0, 2]])
        ax.set_ylim(extent[[1, 3]])
        plot_map_by_var(
            source_gdf["geometry"],
            source_gdf[var_label],
            var_label=var_label,
            legend=False,
            edgecolor="black",
            ax=ax,
            attribution=False,
            set_axis_off=True,
            cmap=cmap,
            vmin=vmin,
            vmax=vmax,
        )
        ax.set_axis_off()
        ax.set_title(source)

    if legend:
        # add colorbar
        sm = plt.cm.ScalarMappable(cmap=cmap, norm=plt.Normalize(vmin=vmin, vmax=vmax))
        # the colorbar is laid out by the constrained layout, so the figure keeps its
        # size when saved rather than relying on `bbox_inches="tight"` to reach a
        # colorbar placed outside of it
        _ = fig.colorbar(
            sm, ax=axes, location="right", shrink=0.6, pad=0.02, label=var_label
        )

    return fig
