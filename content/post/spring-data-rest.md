+++
date = "2016-06-11T09:58:04-05:00"
title = "Spring Data Rest"
description = "How to leverage Spring Data Rest to build a realistic API"
+++

Spring and Java: the enterprise favorites.

The task is building a simple User Management RESTful API.

Our domain consists of *Accounts*, *Groups* and *Roles*. Here's the break down.

<!--more-->

- Accounts have basic user information: first and last name, username, passwords are stored in ldap elsewhere using the magical [Spring LDAP](http://projects.spring.io/spring-ldap/)  - no need to worry about exposing passwords through the API. Accounts are in a *many-to-many* relationship with Groups.
- Groups contain a name, a code (like a short unique human-readable word), and a verbose description. Groups are in a *many-to-many* relationship with Accounts, but also with Roles. Groups are effectively a set of Roles predefined.
- Roles contain a name, a code and a description. Roles are in a *many-to-many* relationship with Groups.

### Routes

Spring Data Rest excels at straight up RESTful HTTP APIs. You can imagine the endpoints now, hopefully.

- `/accounts`, `/accounts/{id}`, `/accounts/{id}/groups`
- `/groups`, `/groups/{id}`, `/groups/{id}/accounts`, `/groups/{id}/roles`
- `/roles`, `/roles/{id}`, `/roles/{id}/groups`

These mirror the `GET` routes perfectly, and of course, the other HTTP verb routes, such as `POST|PUT|PATCH` are supported where they make sense.

### Models

The code for setting this structure up is simple. There are three [POJOs](https://en.wikipedia.org/wiki/Plain_Old_Java_Object), one for each of the domain models. Because each of those domain models is a POJO, they extend nothing, and only implement `Serializable`. Of course, while they *were* only POJOs, one could argue they are no longer *plain*, because various *annotations* will be required because Spring Data Rest leverages [Spring JPA](http://projects.spring.io/spring-data-jpa/).

The `Account.java` is the star of the show.

~~~
@Entity
@Table(name = "accounts")
public class Account {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Integer id;

    // Demo fields.
    private String username;
    private String firstname;
    private String lastname;

    /**
     * Many-To-Many relationship for Accounts to Groups (i.e. Membership).
     */
    @ManyToMany
    @JoinTable(
            name = "accounts_groups_map",
            joinColumns = @JoinColumn(name = "account_id", referencedColumnName = "id"),
            inverseJoinColumns = @JoinColumn(name = "group_id", referencedColumnName = "id")
    )
    private List<Group> groups;
~~~

You can see here:

1. A POJO muddied by the wicked annotations.
2. `GenerationType.IDENTITY` was required for our PostgreSQL database, but `GenerationType.AUTO` will work for MySQL (my preferred database).
3. Various demo fields, username, first and last name.
4. The many-to-many mapping between Accounts and Groups using a [join table](https://en.wikipedia.org/wiki/Associative_entity).

`Group.java` mirrors `Role.java` very closely, except in the latter, the relationship is inverted.

```
@Entity
@Table(name = "groups")
public class Group {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Integer id;

    private String name;
    private String code;
    private String description;

    @ManyToMany
    @JoinTable(
            name = "accounts_groups_map",
            joinColumns = @JoinColumn(name = "group_id", referencedColumnName = "id"),
            inverseJoinColumns = @JoinColumn(name = "account_id", referencedColumnName = "id")
    )
    private List<Account> accounts;

    @ManyToMany
    @JoinTable(
            name = "groups_roles_map",
            joinColumns = @JoinColumn(name = "group_id", referencedColumnName = "id"),
            inverseJoinColumns = @JoinColumn(name = "role_id", referencedColumnName = "id")
    )
    private List<Role> roles;
```

The same major components are found here, as in `Account.java`. The unique part of this POJO is that it has two many-to-many relationships, one for Accounts (as in, this *Group contains these Accounts*), and one for Roles (as in, this *Group has these Roles*).

### Repository (or, a Controller in disguise)

Spring Data Rest is incredibly *magical*. There is so little code to do so much heavy lifting. The traditional approach to building a RESTful API is to use the MVC pattern. In particular, Spring Data Rest obviates the need for the Controller to some degree, because it *magically* handles the role of the controller through a special *repository* annotation.

The `AccountsRepository.java` implements `JpaRepository`, but more importantly, uses the Spring Data Rest annotation `RepositoryRestResource`. The abominable name of this annotation is likely because uses of better names already existing. Despite that, the repository annotation accepts a few parameters, setting up the plural-singular relationship with the collection and item versions of the repository. After that, all of the routes listed above instantly get hooked up and are ready to go (for Accounts, anyway - the same is true, provided the `GroupsRepository.java`  and `RolesRepository.java` are also created).

```
@RepositoryRestResource(
        path = "accounts",
        collectionResourceRel = "accounts",
        itemResourceRel = "account"
)
public interface AccountsRepository extends JpaRepository<Account, Integer> {
  // ...
}
```

One might wonder, what lies within that `// ...` comment? Spring Data Rest allows easy *search* endpoint creation. For example, `/accounts/search/username?q=`, is a route that returns a collection based on the query string value passed to `q`, based on matching partial *usernames*.

```
// ... within AccountsRepository ...
@RestResource(path = "usernames", rel = "usernames")
Page<Account> findByUsernameContaining(@Param("q") String name, Pageable p);
```

1. The `RestResource` exposes the endpoint to the world, based on the `path` value passed in.
2. The endpoint returns a `Page<Account>`, which allows for easy pagination on the client side simply by consuming HATEOAS links - no need to implement `ResourceSupport` or wrap your domain in `Resource` yourself.
3. `@Param("q")` wires the query string parameter to the Java variable `name`.
4. `Pageable p` handles pagination and sorting, and is provided to the repository automatically.

The default searching mechanism should not strike one as very powerful, nor generalized. Effectively, this runs `LIKE %username%` through the database and returns whatever it finds. That is fine, but it might not be enough in all situations.

Spring Data Rest can handle non-RESTful endpoints as well. Suppose, for some reason, you need to occasionally resolve a username to an Account ID. One strategy might be to create a custom endpoint that accepts a username, and returns a `Location` header for the caller to follow to fetch the full account by.

### Projections

Initially, one of our biggest issues was with data fetching. Our API is 80% reads and 20% writes, so optimizing our API for fetching data was our first thought. Because of the relationships in our API, the data itself was highly coupled with each other. Requesting an *Account* might not require the *Groups* of the Account to be listed, but sometimes it might.

Spring Data Rest solves this presentation issue by letting the client decide, at runtime, what kind of depth of data it would like. This is called a *projection*, and one might suspect it is named as such because of [database projection](http://stackoverflow.com/questions/3461099/what-is-a-projection).

*Interfaces* are used to create the projections. By mapping the getters of the projected model class, we can create views the client can decide to use depending on the specific request type.

```
@Projection(name = "extended", types = Account.class)
public interface ExtendedAccount {
    Integer getId();

    String getUsername();
    String getFirstname();
    String getLastname();

    List<Group> getGroups();
}
```

Imagine requesting `/accounts/1` and only getting the account information, but you also needed to show the groups that this account is in too. Instead of making another request to `/accounts/1/groups`, the *extended* projection could be used to *inline* the additional groups data.

Additionally, these projections can be chained together to create paths of extra data. Suppose you required information from Accounts, Groups and Roles, and instead of making multiple requests, it could be easily satisfied with just one.

```
@Projection(name = "complete", types = Account.class)
public interface CompleteAccount {

    Integer getId();

    String getUsername();
    String getFirstname();
    String getLastname();

    List<CompleteGroup> getGroups();
}
```

Here is another Account projection, but this is the *complete* projection. Notice the `getGroups` method returns a list of `List<CompleteGroup>`. This getter specifies that it should return an interface projection list of the `CompleteGroup` type. This is the chaining mechanism that expands the utility of projection by traversing the relationship hierarchy.

```
@Projection(name = "complete", types = Group.class)
public interface CompleteGroup {

    Integer getId();

    String getName();
    String getCode();
    String getDescription();

    List<Role> getRoles();

}
```

This is the follow up projection, using the same *complete* projection name because it is a part of the *complete* chain. `CompleteGroup` has `getRoles`, though that method returns the simple list of roles.  If it were required to further traverse down the chain, it could be done by creating a `CompleteRole` and instead of returning `List<Role>`, returning `List<CompleteRole>`.

### Data Examples

Let's begin with our favorite endpoint, `/accounts/`.

```
{
  "_embedded": {
    "accounts": [
      {
        "id": 1,
        "username": "ryanmr",
        "firstname": "Ryan",
        "lastname": "Rampersad",
        "_links": {
          "self": {
            "href": "http://localhost:8888/accounts/1"
          },
          "account": {
            "href": "http://localhost:8888/accounts/1{?projection}",
            "templated": true
          },
          "groups": {
            "href": "http://localhost:8888/accounts/1/groups"
          }
        }
      }, /*  ... more accounts ... */
    }, /* ... more structures ... */
}
```

This is account data retrieved with no projections, and no special controller apparatus.
