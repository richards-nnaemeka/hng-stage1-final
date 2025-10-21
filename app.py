from flask import Flask

app = Flask(__name__)

@app.route('/')
def hello():
    return '''
    <!DOCTYPE html>
    <html>
    <head>
        <title>HNG Stage 1 - Success</title>
        <style>
            body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
            .success { color: #28a745; font-size: 24px; }
        </style>
    </head>
    <body>
        <h1 class="success">🚀 HNG Stage 1 - Deployment Successful!</h1>
        <p>Automated deployment script working perfectly!</p>
        <p>Timestamp: 2025</p>
    </body>
    </html>
    '''

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
