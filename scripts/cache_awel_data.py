"""Cache the AWEL (canton of Zurich) LoRa sensor series as a raw input.

The monthly files published by AWEL are the authoritative source, and each row carries
the coordinates at which the measurement was taken. This script assembles the summer
(JJA) series directly from them instead of going through the meteora client, which has
two shortcomings for a multi-year study:

- its station roster is derived from the most recent monthly file only, so sensors that
  have since been relocated or decommissioned are dropped from the whole historical
  record, and relocated ones are geolocated at their *current* position;
- its month list is built with a month-start frequency, so the first month is skipped
  whenever the requested period starts mid-month.

Sensors that relocate are split into one station per location, since two locations are
two sampling points: the resulting station id is the bare sensor id when the sensor
never moved, and `<sensor>-<k>` (k ordered by first observation) when it did.
"""

import argparse

import geopandas as gpd
import pandas as pd
import pooch

# AWEL publishes one file per calendar month
TS_ENDPOINT = "https://www.web.statistik.zh.ch/awel/LoRa/data/AWEL_Sensors_LoRa_{year}{month:02}.csv"
TS_COLUMNS = ["starttime", "site", "masl", "magl", "x", "y", "sensor", "temperature"]

# study period: the summer months of the years covered by the analysis
YEARS = [2022, 2023, 2024, 2025]
MONTHS = [6, 7, 8]

# only the sensors mounted at the reference height are comparable
SENSOR_HEIGHT = 2.0

# coordinates are LV95
CRS = "epsg:2056"

DST_TS_DF_FILEPATH = "data/raw/awel-ts-df.csv"
DST_STATIONS_GDF_FILEPATH = "data/raw/awel-stations.gpkg"


def get_monthly_df(year: int, month: int) -> pd.DataFrame:
    """Read one monthly file, keeping the sensors at the reference height.

    Parameters
    ----------
    year, month : int
        Calendar year and month of the file to retrieve.

    Returns
    -------
    pd.DataFrame
        Observations of the month, restricted to `SENSOR_HEIGHT`.
    """
    # pooch caches the downloads, so re-runs only fetch the months that are missing
    filepath = pooch.retrieve(
        TS_ENDPOINT.format(year=year, month=month), known_hash=None
    )
    _df = pd.read_csv(filepath, sep=";", usecols=TS_COLUMNS)
    return _df[_df["magl"] == SENSOR_HEIGHT]


def main(dst_ts_df_filepath: str, dst_stations_gdf_filepath: str) -> None:
    """Assemble the series and station locations and dump them to files.

    Parameters
    ----------
    dst_ts_df_filepath, dst_stations_gdf_filepath : str
        Paths of the hourly time series CSV and of the station locations GeoPackage.
    """
    ts_df = pd.concat(
        [get_monthly_df(year, month) for year in YEARS for month in MONTHS],
        ignore_index=True,
    )
    ts_df["starttime"] = pd.to_datetime(ts_df["starttime"])

    # a sensor that has been moved yields one station per location, ordered by the time
    # at which each location was first observed
    segment_ser = ts_df.groupby(["sensor", "x", "y"])["starttime"].min().rename("since")
    segment_df = segment_ser.reset_index().sort_values(["sensor", "since"])
    segment_df["k"] = segment_df.groupby("sensor").cumcount() + 1
    num_segments_ser = segment_df.groupby("sensor")["k"].transform("max")
    segment_df["station_id"] = (
        segment_df["sensor"]
        .astype(str)
        .where(
            num_segments_ser == 1,
            segment_df["sensor"].astype(str) + "-" + segment_df["k"].astype(str),
        )
    )

    # at this point, each (sensor, x, y) triple maps to exactly one station id
    ts_df = ts_df.merge(
        segment_df[["sensor", "x", "y", "station_id"]], on=["sensor", "x", "y"]
    )

    stations_df = (
        ts_df.groupby("station_id")[["site", "masl", "x", "y"]].first().reset_index()
    )
    stations_gdf = gpd.GeoDataFrame(
        stations_df.drop(columns=["x", "y"]),
        geometry=gpd.points_from_xy(stations_df["x"], stations_df["y"]),
        crs=CRS,
    )

    wide_ts_df = (
        ts_df.pivot_table(index="starttime", columns="station_id", values="temperature")
        .resample("h")
        .mean()
    )
    wide_ts_df.index.name = "time"

    wide_ts_df.to_csv(dst_ts_df_filepath)
    stations_gdf.to_file(dst_stations_gdf_filepath, driver="GPKG")
    print(
        f"cached {wide_ts_df.shape[0]} hourly records for {wide_ts_df.shape[1]}"
        f" stations ({ts_df['sensor'].nunique()} sensors) to {dst_ts_df_filepath}"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--dst-ts-df-filepath", default=DST_TS_DF_FILEPATH, help="time series CSV"
    )
    parser.add_argument(
        "--dst-stations-gdf-filepath",
        default=DST_STATIONS_GDF_FILEPATH,
        help="station locations GeoPackage",
    )
    args = parser.parse_args()
    main(args.dst_ts_df_filepath, args.dst_stations_gdf_filepath)
