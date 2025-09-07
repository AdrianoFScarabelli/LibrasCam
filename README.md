# LibrasCam

Aplicativo capaz de detectar e traduzir em tempo real, sinais de Libras para texto, utilizando a câmera do celular. Desenvolvido em Flutter para dispositivos Android.

Foi utilizada a biblioteca **TensorFlow** para o treinamento de modelos de IA com milhares de imagens de sinais da **Língua Brasileira de Sinais**, além da utilização da biblioteca **MediaPipe** que foi o responsável pela detecção das coordenadas da mão e consequentemente da tradução desses sinais. O código do funcionamento do aplicativo está escrito na linguagem Python e roda como uma Rest API externamente, hospedada em um servidor.

Para hospedar a API da lógica do projeto, foi utilizada a plataforma Hostinger, onde foi utilizado um VPS (Virtual Private Server) para rodar essa aplicação Python externamente e o aplicativo poder se comunicar com ela via requisições http.

**PROJETO EM DESENVOLVIMENTO**
