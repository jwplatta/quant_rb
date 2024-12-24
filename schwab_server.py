from flask import Flask

app = Flask(__name__)

@app.route('/')
def home():
    return "Hello, World! This is your Flask app running on port 8182."

if __name__ == '__main__':
    app.run(port=8182)