Below is a detailed, step‐by‐step guide for setting up the PoC in VS Code. The instructions include bullet points for prerequisites, environment setup, data preparation, building the components, and integrating them into a working pipeline.

---

## 1. Prerequisites and Environment Setup

- **Install VS Code and Python 3.9+**  
    Make sure you have VS Code installed along with a compatible Python version.
    
- **Create a Project Directory**  
    Create a folder (e.g. `financial-chatbot-poc`) for your project.
    
- **Set Up a Python Virtual Environment**  
    Open a terminal in VS Code and run:
    
    ```bash
    python -m venv venv
    source venv/bin/activate   # On Linux/Mac
    # On Windows: venv\Scripts\activate
    ```
    
- **Install Required Python Libraries**  
    In the activated environment, install the necessary packages:
    
    - **OpenAI API client:** `pip install openai`
        
    - **Elasticsearch client:** `pip install elasticsearch`
        
    - **Embedding and NLP support:** `pip install sentence-transformers`
        
    - **Data handling:** `pip install pandas`
        
    - **Graph processing:** Either use an in-memory graph library or connect to Neo4j  
        _For in-memory:_ `pip install networkx`  
        _For Neo4j (optional):_ `pip install neo4j`
        
    - **Workflow Orchestration:** (Assuming LangGraph is available via pip)  
        `pip install langgraph`  
        _(If not available, you can architect your own orchestrator using functions and a directed workflow.)_
        

---

## 2. Set Up Elasticsearch Locally

- **Download and Install Elasticsearch**  
    Follow [Elasticsearch’s installation instructions](https://www.elastic.co/guide/en/elasticsearch/reference/current/install-elasticsearch.html) for your RHEL server.
    
- **Configure Elasticsearch for Vector Search**  
    Create an index with a mapping that includes a dense vector field. For example, create a JSON file (e.g. `index_mapping.json`) with:
    
    ```json
    {
      "mappings": {
        "properties": {
          "text": { "type": "text" },
          "embedding": { "type": "dense_vector", "dims": 384 }
        }
      }
    }
    ```
    
    Then, from a Python script or using curl, create the index:
    
    ```bash
    curl -X PUT "localhost:9200/instruments" -H 'Content-Type: application/json' -d @index_mapping.json
    ```
    

---

## 3. Data Preparation and Extraction

- **Extract Data from Oracle**
    
    - Export the relevant 200 GB subset (e.g., instrument data, rating tables) to CSV or JSON files.
        
    - (Optional) Use the Oracle client library `cx_Oracle` to connect and extract data directly:
        
        ```bash
        pip install cx_Oracle
        ```
        
- **Place Sample Data in Your Project Folder**  
    For the PoC, you might use a smaller sample file (e.g. `instruments_sample.csv`).
    

---

## 4. Building the Knowledge Graph (GraphRAG Component)

- **Design the Graph Schema:**  
    Identify key entities:
    
    - _Instrument Node:_ ISIN, name, type, etc.
        
    - _Rating Nodes:_ Separate nodes or properties for Moody’s and Fitch ratings.
        
    - _Issuer Nodes:_ Issuer name, etc.
        
- **Implement the Graph in Python (using NetworkX):** Create a file `graph_builder.py`:
    
    ```python
    import networkx as nx
    import pandas as pd
    
    def build_knowledge_graph(csv_file):
        # Load sample instrument data
        df = pd.read_csv(csv_file)
        G = nx.DiGraph()
    
        for idx, row in df.iterrows():
            isin = row['isin']
            issuer = row['issuer']
            moodys = row['moodys_rating']
            fitch = row['fitch_rating']
    
            # Add Instrument node
            G.add_node(isin, type='Instrument', name=row['instrument_name'])
            # Add Issuer node (if not already added)
            if issuer not in G:
                G.add_node(issuer, type='Issuer')
            # Create edge between instrument and issuer
            G.add_edge(isin, issuer, relation='issued_by')
    
            # Add ratings as node properties or as separate nodes
            G.nodes[isin]['moodys_rating'] = moodys
            G.nodes[isin]['fitch_rating'] = fitch
    
        return G
    
    if __name__ == "__main__":
        G = build_knowledge_graph("instruments_sample.csv")
        # Example: Query graph for a given ISIN
        test_isin = "US1234567890"
        if test_isin in G.nodes:
            print(f"ISIN: {test_isin}")
            print("Moody's:", G.nodes[test_isin].get('moodys_rating'))
            print("Fitch:", G.nodes[test_isin].get('fitch_rating'))
    ```
    
    This script reads sample data, builds a directed graph, and stores ratings as node attributes.
    

---

## 5. Building the Semantic Search Index (Elasticsearch + Embeddings)

- **Generate Embeddings for Each Document**  
    Create a file `index_documents.py`:
    
    ```python
    from sentence_transformers import SentenceTransformer
    from elasticsearch import Elasticsearch
    import pandas as pd
    
    # Initialize the embedding model (lightweight, fast on CPU)
    model = SentenceTransformer('all-MiniLM-L6-v2')  # 384-dimensional embeddings
    
    # Connect to Elasticsearch
    es = Elasticsearch("http://localhost:9200")
    
    def index_instruments(csv_file, index_name="instruments"):
        df = pd.read_csv(csv_file)
        for idx, row in df.iterrows():
            # Create a text representation for the instrument
            text = f"ISIN: {row['isin']}, Name: {row['instrument_name']}, Issuer: {row['issuer']}, Moody's Rating: {row['moodys_rating']}, Fitch Rating: {row['fitch_rating']}"
            embedding = model.encode(text).tolist()
            doc = {
                "text": text,
                "embedding": embedding
            }
            # Index the document (use ISIN as the id if unique)
            es.index(index=index_name, id=row['isin'], body=doc)
    
    if __name__ == "__main__":
        index_instruments("instruments_sample.csv")
    ```
    
    This script:
    
    - Reads your sample data.
        
    - Generates an embedding using a SentenceTransformer model.
        
    - Indexes each record into Elasticsearch with a dense vector field.
        

---

## 6. Setting Up LangGraph Workflow (Orchestration)

- **Implement a Simple Orchestrator**  
    Create a file `chatbot_orchestrator.py`:
    
    ```python
    import openai
    import json
    from graph_builder import build_knowledge_graph
    from elasticsearch import Elasticsearch
    from sentence_transformers import SentenceTransformer
    import pandas as pd
    
    # Set up your OpenAI API key
    openai.api_key = "YOUR_OPENAI_API_KEY"
    
    # Initialize Elasticsearch and SentenceTransformer
    es = Elasticsearch("http://localhost:9200")
    model = SentenceTransformer('all-MiniLM-L6-v2')
    
    # Build the knowledge graph from sample data
    G = build_knowledge_graph("instruments_sample.csv")
    
    def query_analysis(user_query):
        # Use OpenAI API to extract ISINs and query type
        prompt = f"Extract any ISIN codes and the type of query from: '{user_query}'. Return a JSON with keys 'isins' and 'query_type'."
        response = openai.ChatCompletion.create(
            model="gpt-3.5-turbo",
            messages=[{"role": "user", "content": prompt}]
        )
        result = response['choices'][0]['message']['content']
        return json.loads(result)
    
    def graph_lookup(isins):
        # Look up each ISIN in the knowledge graph
        results = {}
        for isin in isins:
            if isin in G.nodes:
                results[isin] = {
                    "moodys": G.nodes[isin].get('moodys_rating'),
                    "fitch": G.nodes[isin].get('fitch_rating')
                }
            else:
                results[isin] = {"error": "Not found"}
        return results
    
    def vector_search(query_text, index_name="instruments", top_k=3):
        # Embed the query text
        query_vector = model.encode(query_text).tolist()
        # Create Elasticsearch kNN query
        knn_query = {
            "size": top_k,
            "query": {
                "script_score": {
                    "query": {"match_all": {}},
                    "script": {
                        "source": "cosineSimilarity(params.query_vector, 'embedding') + 1.0",
                        "params": {"query_vector": query_vector}
                    }
                }
            }
        }
        response = es.search(index=index_name, body=knn_query)
        hits = response['hits']['hits']
        return [hit['_source'] for hit in hits]
    
    def generate_final_answer(lookup_results):
        # Build a prompt for the final answer
        answer_context = "Here are the retrieved ratings for the provided ISINs:\n\n"
        for isin, data in lookup_results.items():
            if "error" in data:
                answer_context += f"- {isin}: {data['error']}\n"
            else:
                answer_context += f"- {isin}: Moody's: {data['moodys']}, Fitch: {data['fitch']}\n"
        prompt = f"Using the following data, generate a clear and concise answer:\n\n{answer_context}\n\nAnswer:"
        response = openai.ChatCompletion.create(
            model="gpt-3.5-turbo",
            messages=[{"role": "user", "content": prompt}]
        )
        return response['choices'][0]['message']['content']
    
    def main():
        # Example user query
        user_query = "Given these ISINs US1234567890, US0987654321, and US1122334455, find the Moody's and Fitch ratings for each."
        
        # Step 1: Query Analysis
        analysis = query_analysis(user_query)
        isins = analysis.get("isins", [])
        print("Extracted ISINs:", isins)
    
        # Step 2: Knowledge Graph Lookup
        lookup_results = graph_lookup(isins)
        print("Graph Lookup Results:", lookup_results)
    
        # Optional: Additional Vector Search if needed (e.g., for context)
        # context_docs = vector_search(user_query)
        # print("Context Documents from Elastic:", context_docs)
    
        # Step 3: Generate Final Answer using LLM
        final_answer = generate_final_answer(lookup_results)
        print("\nFinal Answer:\n", final_answer)
    
    if __name__ == "__main__":
        main()
    ```
    
    This script outlines the following:
    
    - **Query Analysis:** Uses OpenAI to extract ISINs and determine query type.
        
    - **Graph Lookup:** Searches the in-memory knowledge graph for each ISIN.
        
    - **Optional Vector Search:** (Commented out) retrieves supporting context from Elasticsearch.
        
    - **Answer Generation:** Composes the final answer using the OpenAI API based on structured lookup results.
        

---

## 7. Testing and Debugging

- **Run the Chatbot Pipeline:**  
    In the VS Code terminal (with the virtual environment activated), run:
    
    ```bash
    python chatbot_orchestrator.py
    ```
    
    This should print the extracted ISINs, the lookup results, and finally the final answer from the LLM.
    
- **Use VS Code Debugger:**  
    Set breakpoints in your Python files (e.g., in `chatbot_orchestrator.py`) and run the debugger to step through the process and inspect variables.
    
- **Check Elasticsearch Logs:**  
    If the vector search or indexing isn’t working as expected, review your Elasticsearch logs (and test queries via Kibana or curl).
    

---

## 8. Additional Tips and Next Steps

- **Data Scaling:**  
    Start with a small CSV sample. Once the PoC works, you can adapt the scripts to process larger data sets (or even stream data from Oracle).
    
- **Enhance the Orchestration:**  
    If you have access to the full LangGraph library, explore its more advanced features (like conditional branching and stateful loops) to handle more complex queries and follow-ups.
    
- **Security & API Keys:**  
    Store your OpenAI API key in an environment variable (e.g. using a `.env` file with [python-dotenv](https://pypi.org/project/python-dotenv/)) and load it in your code to avoid hardcoding.
    
- **Documentation & Version Control:**  
    Use Git for version control and document each step and decision within your codebase for future maintenance.
    

---

By following these detailed steps, you can set up and run a PoC that takes natural language queries, uses Elasticsearch for semantic retrieval, builds a knowledge graph from your Oracle data, and orchestrates the entire workflow with LangGraph. This modular design will allow you to extend the system as you move from PoC to production.