import coremltools
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
import os

def summarize_sensor_trace(csv_file: str):
    data = pd.read_csv(csv_file, index_col=False)
    processed = pd.DataFrame()
    attributes = ["AccelX","AccelY","AccelZ","GyroX","GyroY","GyroZ"]
    keep = data.filter(items=attributes)
    processed["mean"] = keep.mean()
    processed["var"] = keep.var()
    return processed

def process_data():
    activities = ['running', 'stationary', 'walking']
    
    pds = []

    path = '/Users/elizabethli/cmsc/mobile/senseMEE/Data/'

    for idx, activity in enumerate(activities):
        current_dir = path + activity
        for file in os.listdir(current_dir):
            file_path = os.path.join(current_dir, file)
            if os.path.isfile(file_path):
                df = summarize_sensor_trace(file_path)
                v = df.unstack().to_frame().sort_index(level=1).T
                v.columns = v.columns.map('_'.join)
                v.insert(0, 'activity', activity)

                pds.append(v)
    
    pd.concat(pds).to_csv('Python/training2.csv')

def make_model():
    attributes = ["mean_AccelX", "var_AccelX",
                  "mean_AccelY", "var_AccelY",
                  "mean_AccelZ", "var_AccelZ", 
                  "mean_GyroX", "var_GyroX",
                  "mean_GyroY", "var_GyroY",
                  "mean_GyroZ", "var_GyroZ"]

    train = pd.read_csv("Python/training2.csv").to_numpy()
    train_x = train[:,2:14]
    train_y = train[:,1]
    model = RandomForestClassifier()
    model.fit(train_x, train_y)

    coreml_model = coremltools.converters.sklearn.convert(model, input_features=attributes)
    coreml_model.save('Python/playlists.mlmodel')

make_model()

