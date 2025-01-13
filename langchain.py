from langchain.agents import create_sql_agent
from langchain.agents.agent_toolkits import SQLDatabaseToolkit
from langchain.sql_database import SQLDatabase
from langchain.llms.openai import OpenAI
import os

# Set your OpenAI API key
os.environ["OPENAI_API_KEY"] = "YOUR_OPENAI_API_KEY"

# Database credentials (replace with your actual credentials)
DB_USER = "your_db_user"
DB_PASSWORD = "your_db_password"
DB_HOST = "your_db_host"
DB_NAME = "your_db_name"

try:
    db = SQLDatabase.from_uri(f"mysql+mysqlconnector://{DB_USER}:{DB_PASSWORD}@{DB_HOST}/{DB_NAME}")
    toolkit = SQLDatabaseToolkit(db=db)
    agent = create_sql_agent(
        llm=OpenAI(temperature=0),  # Temperature 0 for more deterministic results
        toolkit=toolkit,
        verbose=True
    )

    queries = [
        "What is the average balance of all accounts?",
        "How many transactions were made on '2024-07-26'?", #Date format for MySQL
        "What are the names of all customers?",
        "Show me the transaction_id and amount from transactions where account_id is 1",
        "What is the total amount of transactions for account id 1?",
        "Show me the last 5 transactions." # Example using LIMIT
    ]

    for query in queries:
        print(f"\nQuery: {query}")
        try:
            result = agent.run(query)
            print(f"Result: {result}")
        except Exception as e:
            print(f"Error executing query: {e}")

except Exception as e:
    print(f"Error: {e}")
