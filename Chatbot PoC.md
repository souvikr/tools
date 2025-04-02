I want to build a chatbot for a financial reference data system.

The goal is to build a chat interface that will convert natural language queries to fetch relevant information from a relational database.

I have a Oracle 19c database with 5 TB of data.  
I want to build a PoC first where we will use 200 GB for training the model. I will be using open source libraries to build this project.

Use Elasticsearch vectorDb, GraphRAG for knowledge retrieval and Langgraph for orchestrating how that knowledge is processed.  
  
Ask me important questions before making any assumption.


- **Data Access**: What kind of data will be used from the Oracle DB for the PoC? (e.g., specific tables or domains such as securities, counterparties, instrument metadata, etc.)
    
- **Query Scope**: What types of questions or tasks should the chatbot handle initially? (e.g., "What is the ISIN for Apple Inc?" or "List all instruments issued by JPMorgan in 2023")
    
- **Vectorization Strategy**: Will you extract and vectorize structured data (like columnar data) or unstructured text (like comments or documentation)? Or both?
    
- **Model**: Do you have a preferred open-source LLM for the natural language interface? (e.g., Mistral, LLaMA, Falcon?)
    
- **Environment**: What is your current infrastructure setup or preference for running LangGraph and Elasticsearch? (e.g., local setup, Kubernetes, cloud provider?)
    
- **Security/Compliance**: Are there any regulatory or data masking concerns we should consider for PoC development?