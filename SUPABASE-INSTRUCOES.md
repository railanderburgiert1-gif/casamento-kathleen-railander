# Ativar o banco de dados do site

O site já está preparado para enviar confirmações de presença e reservas de presentes para um projeto Supabase. A conexão só será ativada depois de preencher `supabase-config.js` com os dados do projeto.

## 1. Criar o projeto

1. Acesse https://supabase.com/dashboard e crie um projeto.
2. Guarde a senha do banco em local seguro. Ela não é necessária no site.
3. Aguarde o projeto ficar disponível.

## 2. Criar as tabelas e regras de segurança

1. No painel Supabase, abra **SQL Editor**.
2. Abra o arquivo `supabase-setup.sql` deste repositório.
3. Copie todo o conteúdo, cole no SQL Editor e execute.
4. O script cria as tabelas de confirmações, catálogo e reservas, além das políticas RLS. Os dados pessoais dos convidados não ficam públicos.

## 3. Criar o acesso dos noivos

1. No Supabase, abra **Authentication → Users** e crie o usuário com e-mail e senha.
2. No SQL Editor, execute o comando abaixo, substituindo o e-mail pelo e-mail cadastrado:

```sql
insert into private.admin_users (user_id)
select id from auth.users
where lower(email) = lower('EMAIL_DOS_NOIVOS')
on conflict (user_id) do nothing;
```

3. Para outro usuário administrativo, repita o comando com o outro e-mail.
4. Desative o cadastro público de novos usuários em **Authentication → Providers → Email**. Os convidados não precisam criar conta para confirmar presença ou reservar presentes.

## 4. Conectar o site

1. No painel do projeto, copie a **Project URL** e a **Publishable key** (em projetos antigos, pode aparecer como chave `anon`).
2. Abra `supabase-config.js` no repositório e preencha:

```js
window.WEDDING_SUPABASE_CONFIG = {
  url: "https://SEU-PROJETO.supabase.co",
  publishableKey: "SUA_PUBLISHABLE_KEY"
};
```

3. Salve o arquivo. O GitHub Pages publicará a atualização do site.

**Nunca coloque no navegador a Secret key nem a antiga `service_role` key.** A chave publicável só pode ser usada junto com as regras RLS e os privilégios mínimos do banco. O arquivo SQL deste projeto configura essas regras. Consulte também a documentação oficial: https://supabase.com/docs/guides/database/secure-data e https://supabase.com/docs/guides/database/postgres/row-level-security.

## 5. Atualizar um projeto que já está em uso

Se o banco já foi criado com a versão anterior do SQL, abra **SQL Editor** e execute todo o arquivo `supabase-gifts-migration.sql`. Ele adiciona `photo_url` e `sort_order`, cria o bucket público de leitura `gift-photos` e restringe envio, alteração e exclusão de arquivos às contas autorizadas dos noivos. Não execute novamente o script inicial para atualizar um banco em uso.

Depois, entre na área dos noivos, abra **Presentes**, cadastre um item de teste, envie uma imagem JPG/PNG/WebP de até 5 MB e mova o item para cima ou para baixo. Confira a imagem na página pública e exclua o item de teste pelo banco, se necessário. O catálogo permanece vazio até os noivos cadastrarem itens.

## O que passa a funcionar

- Confirmações de presença gravadas em uma base única, consultável pelos noivos em qualquer dispositivo.
- Contagem de confirmações e total de convidados confirmados, considerando acompanhantes.
- Reserva atômica dos presentes: quando alguém reserva um item, ele aparece como reservado para os demais.
- Painel com acesso por e-mail e senha, limitado aos usuários cadastrados na tabela privada de administradores.
- Exportação dos registros para JSON.

Até que a URL e a Publishable key sejam configuradas, o site informa que o formulário online está em configuração e oferece os botões de WhatsApp como alternativa. Nenhuma confirmação é apresentada como salva na nuvem antes da conexão estar ativa.
