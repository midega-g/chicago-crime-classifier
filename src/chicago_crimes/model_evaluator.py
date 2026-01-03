from sklearn.metrics import classification_report, roc_auc_score


def evaluate_model(pipeline, X_dict, y_true, dataset_name="Validation"):
    """Evaluate model performance and return metrics."""
    y_pred_proba = pipeline.predict_proba(X_dict)[:, 1]
    y_pred = pipeline.predict(X_dict)

    auc_score = roc_auc_score(y_true, y_pred_proba)
    classification_rep = classification_report(y_true, y_pred)

    print(f"{dataset_name} AUC-ROC: {auc_score:.4f}")
    print(f"\nClassification Report ({dataset_name}):\n{classification_rep}")

    return {
        "auc_score": auc_score,
        "y_pred_proba": y_pred_proba,
        "y_pred": y_pred,
        "classification_report": classification_rep,
    }
