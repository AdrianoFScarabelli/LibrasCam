# LibrasCam

Aplicativo capaz de detectar e traduzir em tempo real, sinais de **Libras** para texto, utilizando a câmera do celular. Desenvolvido em **Flutter** para dispositivos Android.

Foi utilizada a biblioteca **TensorFlow** para o treinamento de modelos de **IA** com milhares de imagens de mãos realizando sinais da **Língua Brasileira de Sinais**, além da utilização da biblioteca **MediaPipe** que foi o responsável pela detecção das coordenadas da mão e consequentemente da tradução desses sinais. O código do funcionamento do aplicativo está escrito na linguagem **Python** e roda como uma **Rest API** (Representational State Transfer) externamente, hospedada em um servidor.

Para hospedar a API da lógica do projeto, foi escolhida a plataforma de hospedagem de aplicações **Hostinger**, onde foi utilizado um **VPS** (Virtual Private Server) para rodar essa aplicação **Python** externamente e o aplicativo poder se comunicar com ela via requisições http.

A principal ferramenta utilizada na identificação dos sinais de **Libras** foi a **MediaPipe**, ela foi criada pela **Google** visando o desenvolvimento de projetos com aprendizado de máquina, processamento de imagens, videos etc. Com ela, é possivel captar 21 coordenadas da mão, permitindo um tratamento mais apropriado para o projeto em questão. Além disso, ela pode identificar em uma imagem o que é uma mão e o que não é, evitando com que o reconhecimento de imagens confunda objetos, com mãos etc. A seguir é possivel observar as 21 coordenadas (Landmarks) que o **MediaPipe** é capaz de identificar:

<img width="2146" height="744" alt="image" src="https://github.com/user-attachments/assets/855fc63d-583b-4b55-a2b2-aee8c77a20b0" />

**PROJETO EM DESENVOLVIMENTO**
