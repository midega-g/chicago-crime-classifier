# Machine Learning Model Training and Class Imbalance Handling for Arrest Prediction

## Class Weight Computation and Imbalanced Dataset Challenges

The `compute_class_weight` function addresses one of the most critical challenges in the Chicago crime arrest prediction problem: severe class imbalance where arrests occur in only approximately 12% of reported incidents (60,327 arrests out of 503,000 total incidents). This imbalance creates a scenario where a naive model could achieve 88% accuracy by simply predicting "no arrest" for every case, but such a model would be operationally useless for police resource allocation and decision support.

```python
from sklearn.utils.class_weight import compute_class_weight

# Class weights computation
class_weights = compute_class_weight('balanced', classes=np.unique(y_train), y=y_train)
# Output: {0: 0.5681394618601089, 1: 4.168945911449268}
```

The computed class weights reveal the mathematical approach to balancing the dataset during training. Class 0 (no arrest) receives a weight of approximately 0.57, effectively down-weighting the majority class, while Class 1 (arrest) receives a weight of approximately 4.17, significantly up-weighting the minority class. These weights are calculated using the formula: `n_samples / (n_classes * np.bincount(y))`, which ensures that the effective contribution of each class to the loss function is balanced regardless of their natural frequency in the dataset.

The weight ratio of approximately 7.3:1 (4.17/0.57) reflects the inverse of the class distribution ratio, compensating for the natural imbalance by making each arrest case contribute roughly seven times more to the model's learning process than each non-arrest case. This mathematical rebalancing forces the algorithm to pay equal attention to learning patterns that lead to arrests and patterns that lead to non-arrests, rather than being overwhelmed by the majority class.

## Performance Analysis With and Without Class Weights

The impact of class weight balancing becomes evident when comparing model performance across different evaluation scenarios. With balanced class weights, the model achieves a validation AUC-ROC of 0.8729, indicating strong discriminative ability between arrest and non-arrest cases. The classification report reveals a precision of 0.56 and recall of 0.55 for the arrest class (Class 1), demonstrating that the model correctly identifies 55% of actual arrests while maintaining reasonable precision in its arrest predictions.

Without class weight balancing, the model exhibits classic symptoms of majority class bias despite achieving a slightly lower AUC-ROC of 0.8724. The most striking difference appears in the recall for arrest cases, which drops dramatically to 0.39, meaning the model only identifies 39% of actual arrests. However, the precision for arrest predictions increases to 0.83, indicating that when the model does predict an arrest, it is correct 83% of the time, but it makes far fewer such predictions overall.

The trade-off between precision and recall in imbalanced classification scenarios reflects the fundamental business decision facing police departments: whether to prioritize identifying most potential arrests (high recall) at the cost of more false alarms, or to prioritize accuracy when predicting arrests (high precision) while missing more actual arrest opportunities. The balanced approach provides a more operationally useful middle ground where the model identifies a substantial portion of arrest cases while maintaining reasonable precision.

## Classification Report Interpretation and Metric Selection

The classification report provides comprehensive insight into model performance across multiple dimensions, each carrying different operational significance for police resource allocation.

- Precision for the arrest class indicates the proportion of predicted arrests that actually result in arrests, directly relating to the efficiency of resource deployment when the model flags high-probability cases.
- Recall for the arrest class measures the proportion of actual arrests that the model successfully identifies, relating to the completeness of the predictive system in capturing arrest opportunities.
- The macro average metrics (0.75 for precision, recall, and F1-score with class weights) provide unweighted averages across both classes, treating arrest and non-arrest predictions as equally important. This perspective aligns with the operational goal of building a balanced classifier that performs well on both outcomes.
- The weighted average metrics (0.89 across all measures with class weights) reflect performance weighted by class frequency, naturally emphasizing performance on the majority class.

For police operational purposes, **recall for the arrest class holds particular significance** because missing actual arrest opportunities represents lost chances for crime clearance, evidence collection, and public safety improvement. The balanced model's 55% recall means that implementing this system could help police identify and prioritize approximately half of all cases that will ultimately result in arrests, enabling more efficient resource allocation and potentially improving overall clearance rates through better case prioritization.

## Model Parameters and Training Strategy

The XGBoost implementation leverages the computed class weights through the `scale_pos_weight` parameter, which specifically addresses positive class (arrest) under-representation during gradient boosting. This parameter effectively multiplies the gradient of positive examples by the specified weight ratio, ensuring that the algorithm pays proportionally more attention to learning arrest patterns during each boosting iteration.

```python
import xgboost as xgb

# XGBoost with class weight handling
xgb_model = xgb.XGBClassifier(
    scale_pos_weight=class_weights[1]/class_weights[0],  # ~7.3
    random_state=42,
    eval_metric='auc'
)
```

The choice of AUC-ROC as the evaluation metric reflects its appropriateness for imbalanced binary classification problems where the focus is on ranking and discrimination rather than calibrated probability estimates. AUC-ROC measures the model's ability to distinguish between classes across all possible classification thresholds, making it particularly valuable for operational scenarios where the decision threshold can be adjusted based on resource availability and operational priorities.

The training strategy emphasizes temporal validation by using chronological splits (2022-2023 for training, 2024 for validation) rather than random splits, ensuring that the model's performance evaluation reflects its ability to generalize to future crime patterns rather than simply interpolating within historical data. This approach provides more realistic performance estimates for deployment scenarios where the model must predict arrest outcomes for new incidents occurring after the training period.

## Operational Implications and Threshold Selection

The performance differences between balanced and unbalanced training approaches highlight the critical importance of threshold selection in operational deployment. The balanced model provides a foundation for flexible threshold adjustment, where police departments can tune the decision boundary based on current resource availability, seasonal crime patterns, or strategic priorities. During periods of high resource availability, a lower threshold could be used to capture more potential arrests (higher recall), while resource-constrained periods might require higher thresholds to focus on the most confident predictions (higher precision).

The classification report metrics serve as the foundation for cost-benefit analysis in police resource allocation. The balanced model's 56% precision for arrest predictions means that approximately 44% of high-priority cases flagged by the system will not result in arrests, representing the operational cost of false positives in terms of misdirected resources. Conversely, the 55% recall indicates that 45% of actual arrest opportunities will not be flagged as high-priority, representing the opportunity cost of missed cases that could have been resolved more efficiently with proper prioritization.
