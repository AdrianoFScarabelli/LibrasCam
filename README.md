# LibrasCam

Aplicativo capaz de detectar e traduzir em tempo real, sinais de **Libras** para texto, utilizando a câmera do celular. Desenvolvido em **Flutter** para dispositivos Android.

Foi utilizada a biblioteca **TensorFlow** para o treinamento de modelos de **IA** com milhares de imagens de mãos realizando sinais da **Língua Brasileira de Sinais**, além da utilização da biblioteca **MediaPipe** que foi o responsável pela detecção das coordenadas da mão e consequentemente da tradução desses sinais. O código do funcionamento do aplicativo está escrito na linguagem **Python** e roda como uma **Rest API** (Representational State Transfer) externamente, hospedada em um servidor.

Para hospedar a API da lógica do projeto, foi escolhida a plataforma de hospedagem de aplicações **Hostinger**, onde foi utilizado um **VPS** (Virtual Private Server) para rodar essa aplicação **Python** externamente e o aplicativo poder se comunicar com ela via requisições http.

A principal ferramenta utilizada na identificação dos sinais de **Libras** foi a **MediaPipe**, ela foi criada pela **Google** visando o desenvolvimento de projetos com aprendizado de máquina, processamento de imagens, videos etc. Com ela, é possivel captar 21 coordenadas da mão, permitindo um tratamento mais apropriado para o projeto em questão. Além disso, ela pode identificar em uma imagem o que é uma mão e o que não é, evitando com que o reconhecimento de imagens confunda objetos, com mãos etc. A seguir é possivel observar as 21 coordenadas (Landmarks) que o **MediaPipe** é capaz de identificar:

<img width="2146" height="744" alt="image" src="https://github.com/user-attachments/assets/855fc63d-583b-4b55-a2b2-aee8c77a20b0" />

Além do **MediaPipe** e **TensorFlow**, também foi utilizada a biblioteca **NumPy**, essa biblioteca é conhecida pelo seu processamento de grandes arranjos e matrizes de dados, utilizando muitas funções matemáticas para operar essas matrizes. Com essa biblioteca, o processamento das imagens enviadas pelo aplicativo se torna muito mais eficiente, pois o **NumPy** transforma os bytes brutos da imagem em um formato que o **OpenCV** e o **MediaPipe** possam entender e processar de forma muito melhor. Além disso, o **NumPy** se torna muito importante para o treinamento dos modelos **TensorFlow**, pois ele é capaz de transformar as coordenadas X, Y e Z de cada um dos 21 landmarks da mão detectados pelo **MediaPipe** e os coloca em uma lista **Python** simples, que futuramente é transformada em um array **NumPy**, garantindo uma melhor organização desses valores.

Como foi utilizado o framework **Flutter** para o desenvolvimento do aplicativo, foi necessário realizar a conversão dos modelos treinados em **TensorFlow** para **TensorFlow Lite**, garantindo compatibilidade e desempenho adequado em dispositivos móveis.

## Tela inicial do aplicativo LibrasCam

<img width="369" height="800" alt="image" src="https://github.com/user-attachments/assets/edb4fb96-ca61-436c-8e00-2a70cfa30594" />

## Tela informativa do aplicativo LibrasCam

<img width="369" height="800" alt="image" src="https://github.com/user-attachments/assets/ed1cf4e8-d8ed-4192-8c76-dbc124e7da2f" />

## Vídeo demonstrativo do funcionamento do app

<img width="800" height="450" alt="libras" src="https://github.com/user-attachments/assets/a24f555f-ab85-4e0d-b080-22f20a163ad7" />

## Conclusão

Apesar do objetivo ter sido captar 60 sinais, sendo eles os números de 0 a 9, alfabeto completo, 20 saudações e 4 pontuações, todos esses sinais foram adicionados no app e suas devidas lógicas foram implementadas, porém nem todos esses sinais funcionaram com perfeição no aplicativo, cerca de 50 sinais funcionaram bem ou dentro do esperado de acordo com todos os testes realizados. Levando em conta diversos motivos, como por exemplo a iluminação do ambiente, complexidade do sinal de Libras, tempo de resposta, distância da pessoa da câmera do celular etc.

O aplicativo foi apresentado em ambiente acadêmico e posteriormente seu funcionamento foi interrompido por conta da cobrança mensal que estava sendo paga durante o funcionamento do aplicativo e para rodar a **Rest API** hospedada no servidor da plataforma Hostinger.

Confira a publicação do projeto no meu LinkedIn: https://www.linkedin.com/feed/update/urn:li:activity:7416613920188166144/
