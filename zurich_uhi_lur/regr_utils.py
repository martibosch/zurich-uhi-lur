"""Regression utils."""

import geopandas as gpd
import numpy as np
import pandas as pd
from focalpy.diagnostics import moran_residuals
from pandas.api import types as pd_types
from scipy import stats
from sklearn import base as sk_base
from sklearn import feature_selection
from sklearn.metrics import r2_score
from sklearn.model_selection import cross_val_predict
from sklearn.utils.validation import check_is_fitted, validate_data


class SpearmanSFSSelector(feature_selection.SelectorMixin, sk_base.BaseEstimator):
    """Sequential forward selector: Spearman ordering + condition number stopping.

    Features are ranked by absolute Spearman correlation with ``y`` and added
    greedily. A candidate feature is skipped if adding it would push the
    condition number of the current feature matrix above ``condition_threshold``.

    Parameters
    ----------
    condition_threshold : float, default=30.0
        Maximum allowed condition number.

    Attributes
    ----------
    support_mask_ : ndarray of shape (n_features,)
        Boolean mask of selected features.
    selected_features_ : ndarray of str
        Names of the selected features.
    spearman_values_ : ndarray of shape (n_features,)
        Absolute Spearman correlation of each original feature with ``y``.
    """

    def __init__(self, condition_threshold=30.0):
        self.condition_threshold = condition_threshold

    def fit(self, X, y):
        """Fit feature selector."""
        X = validate_data(self, X, dtype="numeric")
        y = np.asarray(y)

        cols = (
            list(self.feature_names_in_)
            if hasattr(self, "feature_names_in_")
            else [str(i) for i in range(X.shape[1])]
        )

        spearman_vals = np.array(
            [abs(stats.spearmanr(X[:, i], y).statistic) for i in range(X.shape[1])]
        )
        spearman_vals = np.nan_to_num(spearman_vals, nan=0.0)
        rank_order = np.argsort(-spearman_vals)

        selected = []
        for i in rank_order:
            candidate = selected + [i]
            cond = np.linalg.cond(X[:, candidate])
            if cond <= self.condition_threshold:
                selected.append(i)

        mask = np.zeros(X.shape[1], dtype=bool)
        mask[selected] = True
        self.support_mask_ = mask
        self.selected_features_ = np.array([cols[i] for i in selected])
        self.spearman_values_ = spearman_vals
        return self

    def _get_support_mask(self):
        check_is_fitted(self, "support_mask_")
        return self.support_mask_


def _vif_given(X, selected, candidate):
    """Variance inflation factor of `candidate` regressed on the `selected` columns."""
    if not selected:
        return 1.0
    # center so that the fit is equivalent to one with an intercept
    a = X[:, selected] - X[:, selected].mean(axis=0)
    b = X[:, candidate] - X[:, candidate].mean()
    ss_tot = float(b @ b)
    if ss_tot <= 0:
        return np.inf
    coef, *_ = np.linalg.lstsq(a, b, rcond=None)
    resid = b - a @ coef
    r2 = 1.0 - float(resid @ resid) / ss_tot
    return np.inf if r2 >= 1 - 1e-12 else 1.0 / (1.0 - r2)


class SpearmanVIFSelector(feature_selection.SelectorMixin, sk_base.BaseEstimator):
    """Sequential forward selector: Spearman ordering + variance inflation admission.

    Features are ranked by absolute Spearman correlation with ``y`` and added greedily.
    A candidate is admitted only if its variance inflation factor against the already
    selected features stays at or below ``vif_threshold``. A backward pass then prunes
    the features that only became redundant once later candidates were admitted.

    ACHTUNG: the sites carry the distinct predictor rows, since each site contributes
    the same row at every time step. Once the retained set spans that row space, any
    further candidate is an exact linear combination of it and its variance inflation
    factor is infinite, which caps the selection at the rank of the site sample without
    an explicit limit. For the same reason the pruning pass is skipped whenever the
    number of distinct rows does not exceed the retained set: on the degenerate
    four-station fit it would otherwise strip the selection below that rank.

    Parameters
    ----------
    vif_threshold : float, default=5.0
        Maximum tolerated variance inflation factor.

    Attributes
    ----------
    support_mask_ : ndarray of shape (n_features,)
        Boolean mask of selected features.
    selected_features_ : ndarray of str
        Names of the selected features.
    spearman_values_ : ndarray of shape (n_features,)
        Absolute Spearman correlation of each original feature with ``y``.
    """

    def __init__(self, vif_threshold=5.0):
        self.vif_threshold = vif_threshold

    def fit(self, X, y):
        """Fit feature selector."""
        X = validate_data(self, X, dtype="numeric")
        y = np.asarray(y)

        cols = (
            list(self.feature_names_in_)
            if hasattr(self, "feature_names_in_")
            else [str(i) for i in range(X.shape[1])]
        )

        spearman_vals = np.array(
            [abs(stats.spearmanr(X[:, i], y).statistic) for i in range(X.shape[1])]
        )
        spearman_vals = np.nan_to_num(spearman_vals, nan=0.0)

        selected = []
        for i in np.argsort(-spearman_vals):
            if _vif_given(X, selected, i) <= self.vif_threshold:
                selected.append(i)

        if len(np.unique(X, axis=0)) > len(selected) + 1:
            while len(selected) > 1:
                vifs = [
                    _vif_given(X, [j for j in selected if j != i], i) for i in selected
                ]
                worst = int(np.argmax(vifs))
                if vifs[worst] <= self.vif_threshold:
                    break
                selected.pop(worst)

        mask = np.zeros(X.shape[1], dtype=bool)
        mask[selected] = True
        self.support_mask_ = mask
        self.selected_features_ = np.array([cols[i] for i in selected])
        self.spearman_values_ = spearman_vals
        return self

    def _get_support_mask(self):
        check_is_fitted(self, "support_mask_")
        return self.support_mask_


def score_pipeline(
    pipe,
    X,
    y,
    *,
    cv=None,
    station_gser=None,
    groups=None,
    spatial_weights=None,
    weights_fn=None,
    rsa_permutations=20,
    importance_fn=None,
    **rsa_kwargs,
):
    """Fit a pipeline and extract scalar metrics and feature importances.

    Parameters
    ----------
    pipe : sklearn.pipeline.Pipeline
        Unfitted pipeline.
    X : pd.DataFrame
        Feature matrix (column names used for feature selection reporting).
    y : array-like
        Target vector.
    cv : sklearn CV splitter, optional
        If provided, the mean cross-validated R² is included as ``r2_cv``.
    station_gser : gpd.GeoSeries, optional
        Station geometries for Moran's I on residuals.
    groups : array-like, optional
        Site identifiers for Moran's I aggregation.
    spatial_weights : libpysal.weights.W, optional
        Pre-built spatial weights matrix. Takes precedence over
        ``station_gser`` / ``weights_fn`` when provided.
    weights_fn : callable, optional
        ``(geopandas.GeoSeries) -> libpysal.weights.W`` passed to
        :func:`focalpy.diagnostics.moran_residuals` when ``spatial_weights``

        is ``None``. Defaults to KNN with k=4.
    rsa_permutations : int, default 20
        Permutations for Moran's I significance test.
    **rsa_kwargs
        Extra keyword arguments forwarded to
        :func:`focalpy.diagnostics.moran_residuals` (e.g. ``seed``).
    importance_fn : callable, optional
        ``(fitted_pipe, X, selected_features) -> dict[str, float]``
        Model-specific feature importance extractor.

    Returns
    -------
    dict
        Always contains ``pipe`` (fitted), ``r2``, ``selected_features``.
        Conditionally contains ``r2_cv``, ``moran_I``, ``moran_p_sim``,
        ``importances``.
    """
    pipe.fit(X, y)
    y_pred = pipe.predict(X)

    fsel = pipe.named_steps.get("fsel")
    selected = (
        list(X.columns[fsel.support_mask_]) if fsel is not None else list(X.columns)
    )

    result = {
        "pipe": pipe,
        "r2": r2_score(y, y_pred),
        "selected_features": selected,
    }

    if cv is not None:
        y_pred_cv = cross_val_predict(sk_base.clone(pipe), X, y, cv=cv)
        result["r2_cv"] = float(r2_score(y, y_pred_cv))
        result["y_pred_cv"] = y_pred_cv

    if station_gser is not None:
        resid = y.values - (result["y_pred_cv"] if cv is not None else y_pred)

        w = spatial_weights if spatial_weights is not None else station_gser
        rsa = moran_residuals(
            resid,
            w,
            groups=groups,
            permutations=rsa_permutations,
            weights_fn=weights_fn,
            **rsa_kwargs,
        )
        result["moran_I"] = rsa["I"]
        result["moran_p_sim"] = rsa["p_sim"]
        result["resid"] = resid

    if importance_fn is not None:
        result["importances"] = importance_fn(pipe, X, selected)

    return result


def get_site_features_gdf(
    site_features_filepath, sites_gdf_filepath, *, extra_columns="source"
):
    """Get site features as a geo-data frame."""
    if pd_types.is_list_like(extra_columns):
        extra_columns = list(extra_columns)
    elif isinstance(extra_columns, str):
        extra_columns = [extra_columns]
    else:
        extra_columns = []
    site_features_gdf = gpd.read_file(sites_gdf_filepath)
    site_id_col = site_features_gdf.columns.difference(["geometry"] + extra_columns)[0]
    site_features_gdf = site_features_gdf.merge(
        pd.read_csv(site_features_filepath), on=site_id_col
    )
    site_features_gdf = site_features_gdf.set_index(site_id_col)
    return site_features_gdf
